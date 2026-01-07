#include <Wire.h>

#include <Adafruit_MPU6050.h>

#include <Adafruit_Sensor.h>



#include "MAX30100_Registers.h"

#include "MAX30100.h"



#include <BLEDevice.h>

#include <BLEServer.h>

#include <BLEUtils.h>

#include <BLE2902.h>



// ===== NUS UUIDs =====

#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"

#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E" // Phone -> ESP32

#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E" // ESP32 -> Phone



// ===== Objects =====

Adafruit_MPU6050 mpu;

MAX30100 sensor;



BLECharacteristic *pTxCharacteristic = nullptr;

BLECharacteristic *pRxCharacteristic = nullptr;

BLEServer *pServer = nullptr;



volatile bool deviceConnected = false;



// ===== Emergency Button =====

const int PIN_EMERGENCY = 27;      // GPIO27

const uint32_t DEBOUNCE_MS = 250;

uint32_t lastBtnMs = 0;

bool lastBtnLevel = HIGH;



// ===== MAX30100 settings (your working ones) =====

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



// MPU6050 timing

unsigned long lastMpuReport = 0;

#define MPU_REPORT_PERIOD_MS 100



// ===== Debug counters =====

uint32_t maxSamples = 0;

uint32_t lastMaxPrint = 0;



// ===== MAX no-sample watchdog =====

uint32_t lastMaxDataMs = 0;

uint32_t maxNoSampleReinits = 0;



// ===== Thresholds received from Flutter (stored) =====

float thrAX = 25, thrAY = 25, thrAZ = 25;

float thrGX = 25, thrGY = 25, thrGZ = 25;

float thrBpmMin = 50, thrBpmMax = 100;

float thrFallDelta = 12;

float thrK = 2.5;




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

  Serial.println("I2C scan done.");

}



// ===== Reinit MAX30100 robustly =====

bool configMax30100() {

  // bazı kütüphanelerde begin() tekrar çağrılabilir

  if (!sensor.begin()) return false;



  sensor.setMode(MAX30100_MODE_SPO2_HR);

  sensor.setLedsCurrent(MAX30100_LED_CURR_27_1MA, MAX30100_LED_CURR_27_1MA);

  sensor.setLedsPulseWidth(MAX30100_SPC_PW_1600US_16BITS);

  sensor.setSamplingRate(MAX30100_SAMPRATE_100HZ);

  sensor.setHighresModeEnabled(true);



  // algoritma state reset (çok önemli!)

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



class MyRxCallbacks : public BLECharacteristicCallbacks {

  void onWrite(BLECharacteristic *pCharacteristic) override {

    String rxValue = pCharacteristic->getValue();

    if (rxValue.length() == 0) return;



    rxValue.trim();

    Serial.print("RX: ");

    Serial.println(rxValue);



    int first = rxValue.indexOf(',');

    if (first < 0) return;



    String type = rxValue.substring(0, first);

    String rest = rxValue.substring(first + 1);

    type.trim();

    rest.trim();



    if (type == "THR") {

      int second = rest.indexOf(',');

      if (second < 0) return;

      String key = rest.substring(0, second);

      String val = rest.substring(second + 1);

      key.trim(); val.trim();



      float f = val.toFloat();



      if (key == "AX") thrAX = f;

      else if (key == "AY") thrAY = f;

      else if (key == "AZ") thrAZ = f;

      else if (key == "GX") thrGX = f;

      else if (key == "GY") thrGY = f;

      else if (key == "GZ") thrGZ = f;

      else if (key == "BPM_MIN") thrBpmMin = f;

      else if (key == "BPM_MAX") thrBpmMax = f;

      else if (key == "FALL") thrFallDelta = f;

      else if (key == "K") thrK = f;



      Serial.printf("THR set %s = %.3f\n", key.c_str(), f);

      return;

    }

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



      Serial.println("EVT,EMERGENCY");

      if (deviceConnected && pTxCharacteristic) {

        const char *msg = "EVT,EMERGENCY";

        pTxCharacteristic->setValue((uint8_t*)msg, strlen(msg));

        pTxCharacteristic->notify();

      }

    }

    if (lastBtnLevel == HIGH) pressedLatched = false;

  }

}



void updateMax30100() {

  sensor.update();


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
  uint16_t rawIR, rawRed;

  bool gotAny = false;



  while (sensor.getRawValues(&rawIR, &rawRed)) {

    gotAny = true;

    maxSamples++;

    lastMaxDataMs = millis();



    lastRawIR = rawIR;

    currentInput = (float)rawIR;



    // DC blocking

    acSignal = alphaDC * (lastAcSignal + currentInput - lastInput);

    lastInput = currentInput;

    lastAcSignal = acSignal;



    // EMA

    filteredSignal = (alphaEMA * acSignal) + ((1.0 - alphaEMA) * filteredSignal);



    // dynamic threshold

    runningMax = runningMax * 0.99;

    if (filteredSignal > runningMax) runningMax = filteredSignal;



    dynamicThreshold = runningMax * thresholdFactor;

    if (dynamicThreshold < minAbsoluteThreshold) dynamicThreshold = minAbsoluteThreshold;



    // finger present heuristic

    finger = (lastRawIR > 2000);



    // peak detect

    bool isPeak = (filteredSignal < prevFilteredSignal) &&

                  (prevFilteredSignal > dynamicThreshold);



    if (isPeak && (millis() - lastBeatTime > minPulseInterval)) {

      long delta = millis() - lastBeatTime;

      lastBeatTime = millis();

      float instantBpm = 60000.0 / delta;



      if (instantBpm > 40 && instantBpm < 200) {

        bpm = (bpm * 0.8) + (instantBpm * 0.2);

      }

    }



    prevFilteredSignal = filteredSignal;

  }



  // 500ms no samples => reinit

  if (!gotAny && (millis() - lastMaxDataMs > 500)) {

    maxNoSampleReinits++;

    Serial.print("[MAX] NO SAMPLES -> REINIT #");

    Serial.println(maxNoSampleReinits);



    // küçük bekleme + tekrar config

    delay(5);

    bool ok = configMax30100();

    Serial.print("[MAX] reinit ok=");

    Serial.println(ok ? "1" : "0");



    // reinit sonrası I2C de kilitliyse, bir kez I2C scan görmek faydalı

    // (çok spam olmasın diye sadece bazı reinitlerde)

    if (maxNoSampleReinits % 5 == 1) {

      i2cScan();

    }

  }

}



void setup() {

  Serial.begin(115200);

  delay(500);



  Serial.println("=== Dual Sensor + BLE (MAX Auto-Reinit) ===");



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

  mpu.setAccelerometerRange(MPU6050_RANGE_8_G);

  mpu.setGyroRange(MPU6050_RANGE_500_DEG);

  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);



  Serial.print("MAX30100...");

  bool ok = configMax30100();

  Serial.println(ok ? "OK" : "FAIL");

  if (!ok) {

    // en azından adres görünüyor mu

    i2cScan();

    while (1) delay(10);

  }



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



  pRxCharacteristic = pService->createCharacteristic(

    CHARACTERISTIC_UUID_RX,

    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR

  );

  pRxCharacteristic->setCallbacks(new MyRxCallbacks());



  pService->start();

  pServer->getAdvertising()->start();

  Serial.println("BLE advertising started");



  lastMaxDataMs = millis();

}



void loop() {

  handleEmergencyButton();

  updateMax30100();



  // MAX samples/s debug

  if (millis() - lastMaxPrint > 1000) {

    lastMaxPrint = millis();

    Serial.print("[MAX] samples/s=");

    Serial.print(maxSamples);

    Serial.print(" lastRawIR=");

    Serial.print(lastRawIR);

    Serial.print(" reinits=");

    Serial.println(maxNoSampleReinits);

    maxSamples = 0;

  }



  if (millis() - lastMpuReport >= MPU_REPORT_PERIOD_MS) {

    lastMpuReport = millis();



    sensors_event_t a, g, temp;

    mpu.getEvent(&a, &g, &temp);



    char out[160];

    snprintf(out, sizeof(out),

      "%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%u,%.2f,%.2f,%.1f,%d",

      a.acceleration.x, a.acceleration.y, a.acceleration.z,

      g.gyro.x, g.gyro.y, g.gyro.z,

      (unsigned)lastRawIR,

      filteredSignal,

      dynamicThreshold,

      bpm,

      finger ? 1 : 0

    );



    Serial.print("AX:"); Serial.print(a.acceleration.x, 2);

    Serial.print(" AY:"); Serial.print(a.acceleration.y, 2);

    Serial.print(" AZ:"); Serial.print(a.acceleration.z, 2);

    Serial.print(" | GX:"); Serial.print(g.gyro.x, 2);

    Serial.print(" GY:"); Serial.print(g.gyro.y, 2);

    Serial.print(" GZ:"); Serial.print(g.gyro.z, 2);

    Serial.print(" | RawIR:"); Serial.print(lastRawIR);

    Serial.print(" Signal:"); Serial.print(filteredSignal, 1);

    Serial.print(" Thr:"); Serial.print(dynamicThreshold, 1);

    Serial.print(" | BPM:");

    if (!finger) Serial.println("Parmak yok");

    else Serial.println(bpm, 1);



    if (deviceConnected && pTxCharacteristic) {

      pTxCharacteristic->setValue((uint8_t*)out, strlen(out));

      pTxCharacteristic->notify();

    }

  }



  delay(5);

}