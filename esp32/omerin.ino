#include <Wire.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>

#include "MAX30100_Registers.h"
#include "MAX30100.h"

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// AI Kutuphaneleri
#include "TensorFlowLite_ESP32.h"
#include "tensorflow/lite/micro/all_ops_resolver.h"
#include "tensorflow/lite/micro/micro_error_reporter.h"
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/schema/schema_generated.h"
#include "tensorflow/lite/version.h"
#include "model.h"

// ===== BLE UUIDs =====
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

// ===== Objects =====
Adafruit_MPU6050 mpu;
MAX30100 sensor;

BLECharacteristic *pTxCharacteristic = nullptr;
BLECharacteristic *pRxCharacteristic = nullptr;
BLEServer *pServer = nullptr;

volatile bool deviceConnected = false;

// ===== AI Degiskenleri =====
#define AI_THRESHOLD 0.90      // %90 ustu dusme sayilir
#define NUM_SAMPLES 128        // Pencere boyutu
#define NUM_CHANNELS 6         // 3 Ivme + 3 Gyro

// TFLite bellek
const int kArenaSize = 60 * 1024;
uint8_t tensor_arena[kArenaSize];
tflite::MicroErrorReporter micro_error_reporter;
tflite::AllOpsResolver resolver;
const tflite::Model* model = nullptr;
tflite::MicroInterpreter* interpreter = nullptr;
TfLiteTensor* input = nullptr;
TfLiteTensor* output = nullptr;

// Veri bufferi
float input_buffer[NUM_SAMPLES * NUM_CHANNELS];
int sample_index = 0;

// Olcekleme katsayilari
const float ACC_SCALE = 0.064; 
const float GYRO_SCALE = 0.005;

// ===== Emergency Button =====
const int PIN_EMERGENCY = 27;       // GPIO27
const uint32_t DEBOUNCE_MS = 250;
uint32_t lastBtnMs = 0;
bool lastBtnLevel = HIGH;

// ===== MAX30100 settings =====
const float alphaDC = 0.95;
const float alphaEMA = 0.2;
const float minAbsoluteThreshold = 20.0;
const float thresholdFactor = 0.8;
const long minPulseInterval = 550;

// MAX30100 variables
float currentInput = 0;
float lastInput = 0;
float acSignal = 0;
float lastAcSignal = 0;
float filteredSignal = 0;
float prevFilteredSignal = 0;
float runningMax = 0;
float dynamicThreshold = 0;
long lastBeatTime = 0;
float bpm = 0;
uint16_t lastRawIR = 0;
bool finger = false;

// Ortalama BPM icin
#define RATE_SIZE 4
byte rates[RATE_SIZE];
byte rateSpot = 0;
float beatAvg = 0;

// MPU6050 timing
unsigned long lastMpuReport = 0;
#define MPU_REPORT_PERIOD_MS 5 // 200Hz icin 5ms

// MAX no-sample watchdog
uint32_t lastMaxDataMs = 0;
uint32_t maxNoSampleReinits = 0;

// ===== I2C scan =====
void i2cScan() {
  Serial.println("I2C scan...");
  for (uint8_t addr = 1; addr < 127; addr++) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      Serial.print(" - Found 0x");
      Serial.println(addr, HEX);
    }
  }
}

// ===== Reinit MAX30100 robustly =====
bool configMax30100() {
  if (!sensor.begin()) return false;

  sensor.setMode(MAX30100_MODE_SPO2_HR);
  sensor.setLedsCurrent(MAX30100_LED_CURR_27_1MA, MAX30100_LED_CURR_27_1MA);
  sensor.setLedsPulseWidth(MAX30100_SPC_PW_1600US_16BITS);
  sensor.setSamplingRate(MAX30100_SAMPRATE_100HZ);
  sensor.setHighresModeEnabled(true);

  // Algoritma reset
  currentInput = lastInput = 0;
  acSignal = lastAcSignal = 0;
  filteredSignal = prevFilteredSignal = 0;
  runningMax = 0;
  dynamicThreshold = 0;
  lastBeatTime = 0;
  bpm = 0;
  lastRawIR = 0;
  finger = false;

  lastMaxDataMs = millis();
  return true;
}

// ===== BLE callbacks =====
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* s) override {
    deviceConnected = true;
    Serial.println(">> BLE connected");
  }
  void onDisconnect(BLEServer* s) override {
    deviceConnected = false;
    Serial.println(">> BLE disconnected -> advertising restart");
    s->getAdvertising()->start();
  }
};

void handleEmergencyButton() {
  bool lvl = digitalRead(PIN_EMERGENCY);
  uint32_t now = millis();

  if (lvl != lastBtnLevel) {
    lastBtnMs = now;
    lastBtnLevel = lvl;
  }

  static bool pressedLatched = false;
  if ((now - lastBtnMs) > DEBOUNCE_MS) {
    if (lastBtnLevel == LOW && !pressedLatched) {
      pressedLatched = true;

      Serial.println("EVT,MANUAL_ALARM");
      if (deviceConnected && pTxCharacteristic) {
        // AI formati ile ayni
        const char *msg = "ALARM,MANUAL,0,0";
        pTxCharacteristic->setValue((uint8_t*)msg, strlen(msg));
        pTxCharacteristic->notify();
      }
    }
    if (lastBtnLevel == HIGH) pressedLatched = false;
  }
}

void updateMax30100() {
  sensor.update();

  uint16_t rawIR, rawRed;
  bool gotAny = false;

  while (sensor.getRawValues(&rawIR, &rawRed)) {
    gotAny = true;
    lastMaxDataMs = millis();

    lastRawIR = rawIR;
    currentInput = (float)rawIR;

    // DC blocking
    acSignal = alphaDC * (lastAcSignal + currentInput - lastInput);
    lastInput = currentInput;
    lastAcSignal = acSignal;

    // EMA
    filteredSignal = (alphaEMA * acSignal) + ((1.0 - alphaEMA) * filteredSignal);

    // Dynamic threshold
    runningMax = runningMax * 0.99;
    if (filteredSignal > runningMax) runningMax = filteredSignal;

    dynamicThreshold = runningMax * thresholdFactor;
    if (dynamicThreshold < minAbsoluteThreshold) dynamicThreshold = minAbsoluteThreshold;

    // Parmak algilama kontrolu
    finger = (lastRawIR > 5000);

    // Peak detect
    bool isPeak = (filteredSignal < prevFilteredSignal) &&
                  (prevFilteredSignal > dynamicThreshold);

    if (isPeak && (millis() - lastBeatTime > minPulseInterval)) {
      long delta = millis() - lastBeatTime;
      lastBeatTime = millis();
      float instantBpm = 60000.0 / delta;

      // Mantikli deger kontrolu (40-200 BPM arasi)
      if (instantBpm > 40 && instantBpm < 200) {
        rates[rateSpot++] = (byte)instantBpm;
        rateSpot %= RATE_SIZE;

        // Ortalama hesapla
        long totalBeat = 0;
        for (byte x = 0; x < RATE_SIZE; x++) {
            totalBeat += rates[x];
        }
        beatAvg = totalBeat / RATE_SIZE;
        bpm = beatAvg;
      }
    }

    prevFilteredSignal = filteredSignal;
  }

  // 500ms no samples => reinit
  if (!gotAny && (millis() - lastMaxDataMs > 500)) {
    maxNoSampleReinits++;
    configMax30100();
  }
}

void setup() {
  Serial.begin(115200);
  delay(500);

  Serial.println("=== Dual Sensor + BLE + AI ===");

  Wire.begin(21, 22);
  Wire.setClock(50000);   //
  Wire.setTimeout(10);    // I2C stuck protection

  pinMode(PIN_EMERGENCY, INPUT_PULLUP);

  Serial.print("MPU6050...");
  if (!mpu.begin(0x68, &Wire)) {
    Serial.println("FAIL");
    while (1) delay(10);
  }
  Serial.println("OK");
  mpu.setAccelerometerRange(MPU6050_RANGE_16_G);
  mpu.setGyroRange(MPU6050_RANGE_2000_DEG);
  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);

  Serial.print("MAX30100...");
  bool ok = configMax30100();
  Serial.println(ok ? "OK" : "FAIL");

  i2cScan();

  BLEDevice::init("ESP32-DUAL");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  pTxCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID_TX,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pTxCharacteristic->addDescriptor(new BLE2902());

  pService->start();
  pServer->getAdvertising()->start();
  Serial.println("BLE advertising started");

  // AI model baslat
  model = tflite::GetModel(g_model);
  static tflite::MicroInterpreter static_interpreter(
      model, resolver, tensor_arena, kArenaSize, &micro_error_reporter);
  interpreter = &static_interpreter;

  interpreter->AllocateTensors();

  input = interpreter->input(0);
  output = interpreter->output(0);

  Serial.println("AI Model Hazir!");
  lastMaxDataMs = millis();
}

void loop() {
  handleEmergencyButton();
  updateMax30100();

  // MPU6050 okuma ve AI
  if (millis() - lastMpuReport >= MPU_REPORT_PERIOD_MS) {
    lastMpuReport = millis();

    sensors_event_t a, g, temp;
    mpu.getEvent(&a, &g, &temp);

    // Verileri normalize et
    float ax = (a.acceleration.x / 9.81) * ACC_SCALE;
    float ay = (a.acceleration.y / 9.81) * ACC_SCALE;
    float az = (a.acceleration.z / 9.81) * ACC_SCALE;
    float gx = g.gyro.x * GYRO_SCALE;
    float gy = g.gyro.y * GYRO_SCALE;
    float gz = g.gyro.z * GYRO_SCALE;

    // Buffer'a at
    int current_pos = sample_index * NUM_CHANNELS;
    input_buffer[current_pos + 0] = ax;
    input_buffer[current_pos + 1] = ay;
    input_buffer[current_pos + 2] = az;
    input_buffer[current_pos + 3] = gx;
    input_buffer[current_pos + 4] = gy;
    input_buffer[current_pos + 5] = gz;

    sample_index++;

    // Buffer doldu mu kontrol et
    if (sample_index >= NUM_SAMPLES) {
      
      // Veriyi input'a kopyala
      for (int i = 0; i < NUM_SAMPLES * NUM_CHANNELS; i++) {
        input->data.f[i] = input_buffer[i];
      }

      // Tahmin yap
      interpreter->Invoke();
      float fall_prob = output->data.f[0];
      
      // Debug
      Serial.print("AI_Score:"); Serial.print(fall_prob);
      Serial.print(" BPM:"); Serial.println(finger ? bpm : 0);

      if (deviceConnected && pTxCharacteristic) {
        char out[64];
        
        // Dusme kontrolu
        if (fall_prob > AI_THRESHOLD) {
            snprintf(out, sizeof(out), "ALARM,FALL,%.2f,%.1f", fall_prob, (finger ? bpm : 0));
        } else {
            snprintf(out, sizeof(out), "DATA,%.2f,%.1f,0", fall_prob, (finger ? bpm : 0));
        }
        
        pTxCharacteristic->setValue((uint8_t*)out, strlen(out));
        pTxCharacteristic->notify();
      }

      // Sifirla
      sample_index = 0;
    }
  }
}