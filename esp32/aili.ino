/*
 * Healthcare Wristlet - Final Version
 * ESP32 + MAX30100 (Heart Rate) + MPU6050 (IMU) + Emergency Button
 * 
 * Flutter uygulaması ile tam uyumlu
 * BLE Nordic UART Service (NUS) kullanır
 * 
 * Veri Formatı (CSV): ax,ay,az,gx,gy,gz,rawIR,filteredSignal,threshold,bpm,finger
 * Emergency Event: EVT,EMERGENCY
 */

#include <Wire.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include "MAX30100_Registers.h"
#include "MAX30100.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <string.h>

// ===== AI / Fall Detection =====
#include "TensorFlowLite_ESP32.h"
#include "tensorflow/lite/micro/all_ops_resolver.h"
#include "tensorflow/lite/micro/micro_error_reporter.h"
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/schema/schema_generated.h"

// Bazı TensorFlowLite_ESP32 portlarında version.h bulunmuyor;
// schema_generated.h genellikle TFLITE_SCHEMA_VERSION sağlar.
#ifndef TFLITE_SCHEMA_VERSION
#define TFLITE_SCHEMA_VERSION 3
#endif
#include "model.h"

// ===== BLE Configuration =====
#define DEVICE_NAME "ESP32-DUAL"

// Nordic UART Service (NUS) UUIDs - Flutter ile uyumlu
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"  // Phone -> ESP32
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"  // ESP32 -> Phone

// ===== Hardware Objects =====
Adafruit_MPU6050 mpu;
MAX30100 sensor;

// ===== BLE Objects =====
BLEServer *pServer = nullptr;
BLECharacteristic *pTxCharacteristic = nullptr;
BLECharacteristic *pRxCharacteristic = nullptr;
volatile bool deviceConnected = false;
volatile bool oldDeviceConnected = false;

// ===== AI / Fall Detection Config =====
#define AI_THRESHOLD 0.90f
#define NUM_SAMPLES 128
#define NUM_CHANNELS 6   // ax, ay, az, gx, gy, gz
const int kArenaSize = 120 * 1024;
uint8_t tensor_arena[kArenaSize];
tflite::MicroErrorReporter micro_error_reporter;
tflite::AllOpsResolver resolver;
const tflite::Model* model = nullptr;
tflite::MicroInterpreter* interpreter = nullptr;
TfLiteTensor* input = nullptr;
TfLiteTensor* output = nullptr;
float input_buffer[NUM_SAMPLES * NUM_CHANNELS];
int sample_index = 0;
unsigned long lastFallNotify = 0;
const unsigned long FALL_COOLDOWN_MS = 5000;

// ===== Emergency Button =====
#define PIN_EMERGENCY 27  // GPIO27
#define DEBOUNCE_MS 250
uint32_t lastBtnMs = 0;
bool lastBtnLevel = HIGH;
bool emergencyLatched = false;

// ===== MAX30100 Heart Rate Algorithm Settings =====
const float alphaDC = 0.95;
const float alphaEMA = 0.2;
const float minAbsoluteThreshold = 20.0;
const float thresholdFactor = 0.8;
const long minPulseInterval = 550;

// MAX30100 Variables
float currentInput = 0;
float lastInput = 0;
float acSignal = 0;
float lastAcSignal = 0;
float filteredSignal = 0;
float prevFilteredSignal = 0;
float runningMax = 0;
float dynamicThreshold = 0;
unsigned long lastBeatTime = 0;
float bpm = 0;
uint16_t lastRawIR = 0;
bool fingerDetected = false;

// ===== Timing =====
#define SENSOR_REPORT_INTERVAL_MS 100  // 10 Hz sensor data
unsigned long lastSensorReport = 0;

// ===== Debug Counters =====
uint32_t maxSamples = 0;
uint32_t lastDebugPrint = 0;
uint32_t lastMaxDataMs = 0;
uint32_t maxReinitCount = 0;

// ===== Thresholds (Flutter'dan alınabilir) =====
float thrAX = 25, thrAY = 25, thrAZ = 25;
float thrGX = 25, thrGY = 25, thrGZ = 25;
float thrBpmMin = 50, thrBpmMax = 100;

// AI normalize scale factors (same as omerin.ino)
const float ACC_SCALE = 0.064f;
const float GYRO_SCALE = 0.005f;

// ========================================
// I2C Scanner (Debug için)
// ========================================
void scanI2C() {
  Serial.println("[I2C] Scanning...");
  for (uint8_t addr = 1; addr < 127; addr++) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      Serial.printf("[I2C] Found device at 0x%02X\n", addr);
    }
  }
  Serial.println("[I2C] Scan complete");
}

// ========================================
// MAX30100 Configuration
// ========================================
bool initMAX30100() {
  if (!sensor.begin()) {
    return false;
  }
  
  sensor.setMode(MAX30100_MODE_SPO2_HR);
  sensor.setLedsCurrent(MAX30100_LED_CURR_27_1MA, MAX30100_LED_CURR_27_1MA);
  sensor.setLedsPulseWidth(MAX30100_SPC_PW_1600US_16BITS);
  sensor.setSamplingRate(MAX30100_SAMPRATE_100HZ);
  sensor.setHighresModeEnabled(true);
  
  // Algorithm state reset
  currentInput = lastInput = 0;
  acSignal = lastAcSignal = 0;
  filteredSignal = prevFilteredSignal = 0;
  runningMax = 0;
  dynamicThreshold = 0;
  lastBeatTime = 0;
  bpm = 0;
  lastRawIR = 0;
  fingerDetected = false;
  lastMaxDataMs = millis();
  
  return true;
}

// ========================================
// AI / Fall Detection Initialization
// ========================================
bool initAI() {
  Serial.println("[AI] Initializing fall detection model...");
  model = tflite::GetModel(g_model);
  if (model->version() != TFLITE_SCHEMA_VERSION) {
    Serial.println("[AI] Model schema version mismatch");
    return false;
  }

  static tflite::MicroInterpreter static_interpreter(
      model, resolver, tensor_arena, kArenaSize, &micro_error_reporter);
  interpreter = &static_interpreter;

  if (interpreter->AllocateTensors() != kTfLiteOk) {
    Serial.println("[AI] AllocateTensors failed");
    return false;
  }

  input = interpreter->input(0);
  output = interpreter->output(0);
  Serial.printf("[AI] input type=%d bytes=%d\n", input->type, input->bytes);

  Serial.println("[AI] Ready");
  return true;
}

// ========================================
// AI / Fall Detection Processing
// ========================================
void processFallDetection(float ax, float ay, float az, float gx, float gy, float gz) {
  // Normalize and push into ring buffer
  int pos = sample_index * NUM_CHANNELS;
  input_buffer[pos + 0] = ax * ACC_SCALE;
  input_buffer[pos + 1] = ay * ACC_SCALE;
  input_buffer[pos + 2] = az * ACC_SCALE;
  input_buffer[pos + 3] = gx * GYRO_SCALE;
  input_buffer[pos + 4] = gy * GYRO_SCALE;
  input_buffer[pos + 5] = gz * GYRO_SCALE;

  sample_index++;

  if (sample_index < NUM_SAMPLES) return;

  // Copy window into model input
  for (int i = 0; i < NUM_SAMPLES * NUM_CHANNELS; i++) {
    input->data.f[i] = input_buffer[i];
  }

  if (interpreter->Invoke() != kTfLiteOk) {
    Serial.println("[AI] Invoke failed");
    sample_index = 0;
    return;
  }

  float fall_prob = output->data.f[0];
  sample_index = 0;

  Serial.printf("[AI] Score: %.2f | BPM: %.1f\n", fall_prob, bpm);

  // Throttle notifications to avoid spamming BLE
  unsigned long now = millis();
  if (fall_prob > AI_THRESHOLD && (now - lastFallNotify) > FALL_COOLDOWN_MS) {
    lastFallNotify = now;
    if (deviceConnected && pTxCharacteristic) {
      char out[64];
      snprintf(out, sizeof(out), "ALARM,FALL,%.2f,%.1f", fall_prob, bpm);
      pTxCharacteristic->setValue((uint8_t*)out, strlen(out));
      pTxCharacteristic->notify();
      Serial.println("[BLE TX] Fall alarm sent");
    }
  }
}

// ========================================
// BLE Server Callbacks
// ========================================
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    deviceConnected = true;
    Serial.println("[BLE] Client connected");
  }
  
  void onDisconnect(BLEServer* pServer) override {
    deviceConnected = false;
    Serial.println("[BLE] Client disconnected");
  }
};

// ========================================
// BLE RX Callbacks (Flutter'dan gelen komutlar)
// ========================================
class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) override {
    String rxValue = pCharacteristic->getValue();
    if (rxValue.length() == 0) return;
    
    rxValue.trim();
    Serial.printf("[BLE RX] %s\n", rxValue.c_str());
    
    // Parse command: THR,KEY,VALUE
    int firstComma = rxValue.indexOf(',');
    if (firstComma < 0) return;
    
    String cmdType = rxValue.substring(0, firstComma);
    String rest = rxValue.substring(firstComma + 1);
    cmdType.trim();
    rest.trim();
    
    if (cmdType == "THR") {
      int secondComma = rest.indexOf(',');
      if (secondComma < 0) return;
      
      String key = rest.substring(0, secondComma);
      String val = rest.substring(secondComma + 1);
      key.trim();
      val.trim();
      
      float value = val.toFloat();
      
      if (key == "AX") thrAX = value;
      else if (key == "AY") thrAY = value;
      else if (key == "AZ") thrAZ = value;
      else if (key == "GX") thrGX = value;
      else if (key == "GY") thrGY = value;
      else if (key == "GZ") thrGZ = value;
      else if (key == "BPM_MIN") thrBpmMin = value;
      else if (key == "BPM_MAX") thrBpmMax = value;
      
      Serial.printf("[THR] Set %s = %.2f\n", key.c_str(), value);
    }
  }
};

// ========================================
// BLE Initialization
// ========================================
void initBLE() {
  Serial.println("[BLE] Initializing...");
  
  BLEDevice::init(DEVICE_NAME);
  
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());
  
  // Create NUS Service
  BLEService *pService = pServer->createService(SERVICE_UUID);
  
  // TX Characteristic (ESP32 -> Phone) - NOTIFY
  pTxCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID_TX,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pTxCharacteristic->addDescriptor(new BLE2902());
  
  // RX Characteristic (Phone -> ESP32) - WRITE
  pRxCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID_RX,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  pRxCharacteristic->setCallbacks(new RxCallbacks());
  
  pService->start();
  
  // Start Advertising with name and service UUID
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  pAdvertising->start();
  
  Serial.printf("[BLE] Advertising as '%s'\n", DEVICE_NAME);
  Serial.printf("[BLE] Service UUID: %s\n", SERVICE_UUID);
}

// ========================================
// Emergency Button Handler
// ========================================
void handleEmergencyButton() {
  bool currentLevel = digitalRead(PIN_EMERGENCY);
  uint32_t now = millis();
  
  // Debounce
  if (currentLevel != lastBtnLevel) {
    lastBtnMs = now;
    lastBtnLevel = currentLevel;
  }
  
  if ((now - lastBtnMs) > DEBOUNCE_MS) {
    // Button pressed (LOW when pressed with INPUT_PULLUP)
    if (lastBtnLevel == LOW && !emergencyLatched) {
      emergencyLatched = true;
      
      Serial.println("[EMERGENCY] Button pressed!");
      
      // Send emergency event via BLE
      if (deviceConnected && pTxCharacteristic) {
        const char* msg = "EVT,EMERGENCY";
        pTxCharacteristic->setValue((uint8_t*)msg, strlen(msg));
        pTxCharacteristic->notify();
        Serial.println("[BLE TX] EVT,EMERGENCY");
      }
    }
    
    // Button released
    if (lastBtnLevel == HIGH) {
      emergencyLatched = false;
    }
  }
}

// ========================================
// MAX30100 Update & Heart Rate Detection
// ========================================
void updateHeartRate() {
  sensor.update();
  
  uint16_t rawIR, rawRed;
  bool gotSample = false;
  
  while (sensor.getRawValues(&rawIR, &rawRed)) {
    gotSample = true;
    maxSamples++;
    lastMaxDataMs = millis();
    
    lastRawIR = rawIR;
    currentInput = (float)rawIR;
    
    // DC Blocking Filter
    acSignal = alphaDC * (lastAcSignal + currentInput - lastInput);
    lastInput = currentInput;
    lastAcSignal = acSignal;
    
    // EMA Low-pass Filter
    filteredSignal = (alphaEMA * acSignal) + ((1.0 - alphaEMA) * filteredSignal);
    
    // Dynamic Threshold
    runningMax = runningMax * 0.99;
    if (filteredSignal > runningMax) {
      runningMax = filteredSignal;
    }
    
    dynamicThreshold = runningMax * thresholdFactor;
    if (dynamicThreshold < minAbsoluteThreshold) {
      dynamicThreshold = minAbsoluteThreshold;
    }
    
    // Finger Detection
    fingerDetected = (lastRawIR > 2000);
    
    // Peak Detection for BPM
    bool isPeak = (filteredSignal < prevFilteredSignal) && 
                  (prevFilteredSignal > dynamicThreshold);
    
    if (isPeak && (millis() - lastBeatTime > minPulseInterval)) {
      unsigned long delta = millis() - lastBeatTime;
      lastBeatTime = millis();
      float instantBpm = 60000.0 / delta;
      
      if (instantBpm > 40 && instantBpm < 200) {
        bpm = (bpm * 0.8) + (instantBpm * 0.2);  // Smoothing
      }
    }
    
    prevFilteredSignal = filteredSignal;
  }
  
  // Watchdog: No samples for 500ms -> reinit sensor
  if (!gotSample && (millis() - lastMaxDataMs > 500)) {
    maxReinitCount++;
    Serial.printf("[MAX30100] No samples, reinit #%u\n", maxReinitCount);
    delay(5);
    initMAX30100();
  }
}

// ========================================
// Send Sensor Data via BLE
// ========================================
void sendSensorData() {
  if (millis() - lastSensorReport < SENSOR_REPORT_INTERVAL_MS) {
    return;
  }
  lastSensorReport = millis();
  
  // Read MPU6050
  sensors_event_t accel, gyro, temp;
  mpu.getEvent(&accel, &gyro, &temp);
  
  // Feed AI fall detector
  processFallDetection(
    accel.acceleration.x,
    accel.acceleration.y,
    accel.acceleration.z,
    gyro.gyro.x,
    gyro.gyro.y,
    gyro.gyro.z
  );

  // Format: ax,ay,az,gx,gy,gz,rawIR,filteredSignal,threshold,bpm,finger
  char dataBuffer[160];
  snprintf(dataBuffer, sizeof(dataBuffer),
    "%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%u,%.2f,%.2f,%.1f,%d",
    accel.acceleration.x, accel.acceleration.y, accel.acceleration.z,
    gyro.gyro.x, gyro.gyro.y, gyro.gyro.z,
    (unsigned)lastRawIR,
    filteredSignal,
    dynamicThreshold,
    bpm,
    fingerDetected ? 1 : 0
  );
  
  // Debug print to Serial
  Serial.printf("AX:%.2f AY:%.2f AZ:%.2f | GX:%.2f GY:%.2f GZ:%.2f | IR:%u BPM:%.1f Finger:%s\n",
    accel.acceleration.x, accel.acceleration.y, accel.acceleration.z,
    gyro.gyro.x, gyro.gyro.y, gyro.gyro.z,
    lastRawIR, bpm, fingerDetected ? "Yes" : "No"
  );
  
  // Send via BLE if connected
  if (deviceConnected && pTxCharacteristic) {
    pTxCharacteristic->setValue((uint8_t*)dataBuffer, strlen(dataBuffer));
    pTxCharacteristic->notify();
  }
}

// ========================================
// Handle BLE Reconnection
// ========================================
void handleBLEReconnection() {
  // Disconnected -> restart advertising
  if (!deviceConnected && oldDeviceConnected) {
    delay(500);  // Give stack time
    pServer->startAdvertising();
    Serial.println("[BLE] Restarting advertising...");
    oldDeviceConnected = deviceConnected;
  }
  
  // New connection
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }
}

// ========================================
// Debug Stats
// ========================================
void printDebugStats() {
  if (millis() - lastDebugPrint < 5000) {
    return;
  }
  lastDebugPrint = millis();
  
  Serial.println("========== Debug Stats ==========");
  Serial.printf("BLE Connected: %s\n", deviceConnected ? "Yes" : "No");
  Serial.printf("MAX30100 samples/5s: %u, reinits: %u\n", maxSamples, maxReinitCount);
  Serial.printf("Heart Rate: %.1f BPM, Finger: %s\n", bpm, fingerDetected ? "Detected" : "Not detected");
  Serial.println("=================================");
  maxSamples = 0;
}

// ========================================
// SETUP
// ========================================
void setup() {
  Serial.begin(115200);
  delay(500);
  
  Serial.println("\n========================================");
  Serial.println("  Healthcare Wristlet - Final Version");
  Serial.println("  ESP32 + MAX30100 + MPU6050 + BLE");
  Serial.println("========================================\n");
  
  // Initialize I2C
  Wire.begin(21, 22);
  Wire.setClock(50000);
  Wire.setTimeout(10);
  
  // Scan I2C devices
  scanI2C();
  
  // Initialize Emergency Button
  pinMode(PIN_EMERGENCY, INPUT_PULLUP);
  Serial.println("[GPIO] Emergency button on GPIO27");
  
  // Initialize MPU6050
  Serial.print("[MPU6050] Initializing... ");
  if (!mpu.begin(0x68, &Wire)) {
    Serial.println("FAILED!");
    while (1) delay(10);
  }
  Serial.println("OK");
  mpu.setAccelerometerRange(MPU6050_RANGE_8_G);
  mpu.setGyroRange(MPU6050_RANGE_500_DEG);
  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
  
  // Initialize MAX30100
  Serial.print("[MAX30100] Initializing... ");
  if (!initMAX30100()) {
    Serial.println("FAILED!");
    scanI2C();
    while (1) delay(10);
  }
  Serial.println("OK");

  // Initialize AI fall detection
  if (!initAI()) {
    Serial.println("[AI] Failed to init model, fall detection disabled");
  }
  
  // Initialize BLE
  initBLE();
  
  Serial.println("\n[READY] Waiting for BLE connection...\n");
}

// ========================================
// LOOP
// ========================================
void loop() {
  // Handle emergency button
  handleEmergencyButton();
  
  // Update heart rate sensor
  updateHeartRate();
  
  // Send sensor data via BLE
  sendSensorData();
  
  // Handle BLE reconnection
  handleBLEReconnection();
  
  // Print debug stats every 5 seconds
  printDebugStats();
  
  delay(5);
}
