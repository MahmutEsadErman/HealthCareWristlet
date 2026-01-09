/*
 * Healthcare Wristlet - Final Version
 * ESP32 + MAX30100 (Heart Rate) + MPU6050 (IMU) + Emergency Button
 * 
 * Flutter uygulaması ile tam uyumlu
 * BLE Nordic UART Service (NUS) kullanır
 * 
 * Veri Formatı (CSV): bpm,finger,inactivity
 * Emergency Event: EVT,EMERGENCY
 * Inactivity Alert: EVT,INACTIVITY
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

// ===== BLE Configuration =====
#define DEVICE_NAME "HealthCareWristlet"

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

// ===== Inactivity Detection =====
#define INACTIVITY_WINDOW_MS 60000     // 1 dakika pencere
#define INACTIVITY_CHECK_INTERVAL_MS 100  // 100ms aralıklarla kontrol
#define MOVEMENT_THRESHOLD 1.0f        // Hareket eşiği (m/s²)
#define GYRO_THRESHOLD 0.7f            // Jiroskop eşiği (rad/s)

unsigned long inactivityWindowStart = 0;
uint32_t movementCount = 0;           // Pencere içinde hareket sayısı
uint32_t totalSamplesInWindow = 0;    // Pencere içinde toplam örnek sayısı
bool inactivityDetected = false;      // Hareketsizlik durumu
bool inactivityAlertSent = false;     // Alert gönderildi mi?
float lastAx = 0, lastAy = 0, lastAz = 0;  // Son ivme değerleri
unsigned long lastInactivityCheck = 0;

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
  dynamicThreshold = minAbsoluteThreshold;
  lastBeatTime = 0;
  bpm = 0;
  lastRawIR = 0;
  fingerDetected = false;
  lastMaxDataMs = millis();
  
  return true;
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
  pAdvertising->setMinPreferred(0x06);  // Min connection interval
  pAdvertising->setMaxPreferred(0x12);  // Max connection interval
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
// Inactivity Detection - Hareketsizlik Algılama
// ========================================
void checkInactivity() {
  if (millis() - lastInactivityCheck < INACTIVITY_CHECK_INTERVAL_MS) {
    return;
  }
  lastInactivityCheck = millis();
  
  // Read MPU6050
  sensors_event_t accel, gyro, temp;
  mpu.getEvent(&accel, &gyro, &temp);
  
  float ax = accel.acceleration.x;
  float ay = accel.acceleration.y;
  float az = accel.acceleration.z;
  float gx = abs(gyro.gyro.x);
  float gy = abs(gyro.gyro.y);
  float gz = abs(gyro.gyro.z);
  
  // Hareket değişimi hesapla (önceki değerlerle karşılaştır)
  float deltaAx = abs(ax - lastAx);
  float deltaAy = abs(ay - lastAy);
  float deltaAz = abs(az - lastAz);
  
  // Son değerleri güncelle
  lastAx = ax;
  lastAy = ay;
  lastAz = az;
  
  // Hareket tespit edildi mi?
  bool isMoving = (deltaAx > MOVEMENT_THRESHOLD) || 
                  (deltaAy > MOVEMENT_THRESHOLD) || 
                  (deltaAz > MOVEMENT_THRESHOLD) ||
                  (gx > GYRO_THRESHOLD) ||
                  (gy > GYRO_THRESHOLD) ||
                  (gz > GYRO_THRESHOLD);
  
  // *** IMMEDIATE ACTIVITY DETECTION ***
  // If patient was inactive and now moving, send activity event IMMEDIATELY
  if (inactivityDetected && isMoving) {
    inactivityDetected = false;
    inactivityAlertSent = false;
    
    Serial.println("[INACTIVITY] ✓ IMMEDIATE Activity detected!");
    
    // Send activity event via BLE immediately
    if (deviceConnected && pTxCharacteristic) {
      const char* msg = "EVT,ACTIVITY";
      pTxCharacteristic->setValue((uint8_t*)msg, strlen(msg));
      pTxCharacteristic->notify();
      Serial.println("[BLE TX] EVT,ACTIVITY");
    }
    
    // Reset window to start fresh
    inactivityWindowStart = millis();
    movementCount = 0;
    totalSamplesInWindow = 0;
    return;
  }
  
  totalSamplesInWindow++;
  if (isMoving) {
    movementCount++;
  }
  
  // 1 dakikalık pencere doldu mu? (only for detecting INACTIVITY)
  if (millis() - inactivityWindowStart >= INACTIVITY_WINDOW_MS) {
    // Hareket oranını hesapla
    float movementRatio = (totalSamplesInWindow > 0) ? 
                          (float)movementCount / totalSamplesInWindow : 0;
    
    // %5'ten az hareket varsa hareketsizlik
    bool wasInactive = (movementRatio < 0.05f);
    
    Serial.printf("[INACTIVITY] Window complete: %u/%u moves (%.1f%%), Inactive: %s\n",
      movementCount, totalSamplesInWindow, movementRatio * 100.0f,
      wasInactive ? "YES" : "NO");
    
    // Hareketsizlik tespit edildi mi?
    if (wasInactive && !inactivityDetected) {
      inactivityDetected = true;
      inactivityAlertSent = false;
      Serial.println("[INACTIVITY] ⚠️ INACTIVITY DETECTED!");
      
      // Send inactivity alert via BLE
      if (deviceConnected && pTxCharacteristic) {
        const char* msg = "EVT,INACTIVITY";
        pTxCharacteristic->setValue((uint8_t*)msg, strlen(msg));
        pTxCharacteristic->notify();
        Serial.println("[BLE TX] EVT,INACTIVITY");
        inactivityAlertSent = true;
      }
    }
    
    // Pencereyi sıfırla
    inactivityWindowStart = millis();
    movementCount = 0;
    totalSamplesInWindow = 0;
  }
}

// ========================================
// Send Sensor Data via BLE
// Format: bpm,finger,inactivity
// ========================================
void sendSensorData() {
  if (millis() - lastSensorReport < SENSOR_REPORT_INTERVAL_MS) {
    return;
  }
  lastSensorReport = millis();
  
  // Sadeleştirilmiş format: bpm,finger,inactivity
  char dataBuffer[64];
  snprintf(dataBuffer, sizeof(dataBuffer),
    "%.1f,%d,%d",
    bpm,
    fingerDetected ? 1 : 0,
    inactivityDetected ? 1 : 0
  );
  
  // Debug print to Serial
  Serial.printf("BPM:%.1f Finger:%s Inactive:%s\n",
    bpm, 
    fingerDetected ? "Yes" : "No",
    inactivityDetected ? "YES!" : "No"
  );
  
  // Send via BLE if connected
  if (deviceConnected && pTxCharacteristic) {
    pTxCharacteristic->setValue((uint8_t*)dataBuffer, strlen(dataBuffer));
    pTxCharacteristic->notify();
    Serial.printf("[BLE TX] %s\n", dataBuffer);
  } else if (!deviceConnected) {
    // Debug: show that we're not sending because not connected
    static uint32_t lastNotConnectedLog = 0;
    if (millis() - lastNotConnectedLog > 5000) {
      Serial.println("[BLE] Not connected, data not sent");
      lastNotConnectedLog = millis();
    }
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
  
  // Check for inactivity (1 min window)
  checkInactivity();
  
  // Send sensor data via BLE
  sendSensorData();
  
  // Handle BLE reconnection
  handleBLEReconnection();
  
  // Print debug stats every 5 seconds
  printDebugStats();
  
  delay(5);
}