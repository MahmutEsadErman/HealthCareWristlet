/*
 * Healthcare Wristlet BLE Sensor Data Sender - ESP32 Version
 * Sends heart rate, IMU (accelerometer + gyroscope), and panic button data
 * Compatible with Flutter app sensor_data_model.dart
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>

// BLE Service and Characteristics UUIDs
#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define HEART_RATE_CHAR_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define IMU_CHAR_UUID "beb5483f-36e1-4688-b7f5-ea07361b26a8"
#define BUTTON_CHAR_UUID "beb54840-36e1-4688-b7f5-ea07361b26a8"

// BLE objects
BLEServer* pServer = NULL;
BLECharacteristic* heartRateChar = NULL;
BLECharacteristic* imuChar = NULL;
BLECharacteristic* buttonChar = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// Timing variables
unsigned long lastHeartRateTime = 0;
unsigned long lastIMUTime = 0;
unsigned long lastButtonTime = 0;

const unsigned long HEART_RATE_INTERVAL = 1000; // 1 second
const unsigned long IMU_INTERVAL = 100;         // 100ms (10Hz)
const unsigned long BUTTON_INTERVAL = 500;      // 500ms

// Example sensor values
float heartRateValue = 75.0;
float accelX = 0.1, accelY = 0.2, accelZ = 9.8;
float gyroX = 0.01, gyroY = 0.02, gyroZ = 0.03;
bool panicButtonStatus = false;

// BLE Server Callbacks
class MyServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("Device Connected");
  }

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("Device Disconnected");
  }
};

void setup() {
  Serial.begin(115200);
  Serial.println("Healthcare Wristlet BLE Sensor - ESP32");
  
  // Initialize BLE
  BLEDevice::init("HealthWristlet");
  
  // Create BLE Server
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // Create BLE Service
  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Create BLE Characteristics
  heartRateChar = pService->createCharacteristic(
    HEART_RATE_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  heartRateChar->addDescriptor(new BLE2902());

  imuChar = pService->createCharacteristic(
    IMU_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  imuChar->addDescriptor(new BLE2902());

  buttonChar = pService->createCharacteristic(
    BUTTON_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  buttonChar->addDescriptor(new BLE2902());

  // Start the service
  pService->start();

  // Start advertising
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("BLE device active, waiting for connections...");
}

void loop() {
  // Handle device connection changes
  if (!deviceConnected && oldDeviceConnected) {
    delay(500); // Give the bluetooth stack time to get ready
    pServer->startAdvertising();
    Serial.println("Start advertising");
    oldDeviceConnected = deviceConnected;
  }
  
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }

  // Send data when connected
  if (deviceConnected) {
    unsigned long currentTime = millis();

    // Send heart rate data
    if (currentTime - lastHeartRateTime >= HEART_RATE_INTERVAL) {
      sendHeartRateData();
      lastHeartRateTime = currentTime;
    }

    // Send IMU data
    if (currentTime - lastIMUTime >= IMU_INTERVAL) {
      sendIMUData();
      lastIMUTime = currentTime;
    }

    // Send button data
    if (currentTime - lastButtonTime >= BUTTON_INTERVAL) {
      sendButtonData();
      lastButtonTime = currentTime;
    }

    // Simulate sensor value changes
    updateSensorValues();
  }
}

void sendHeartRateData() {
  StaticJsonDocument<128> doc;
  
  doc["value"] = heartRateValue;
  doc["timestamp"] = getISO8601Timestamp();

  String jsonString;
  serializeJson(doc, jsonString);

  heartRateChar->setValue(jsonString.c_str());
  heartRateChar->notify();
  
  Serial.print("Heart Rate: ");
  Serial.println(jsonString);
}

void sendIMUData() {
  StaticJsonDocument<256> doc;
  
  doc["x_axis"] = accelX;
  doc["y_axis"] = accelY;
  doc["z_axis"] = accelZ;
  doc["gx"] = gyroX;
  doc["gy"] = gyroY;
  doc["gz"] = gyroZ;
  doc["timestamp"] = getISO8601Timestamp();

  String jsonString;
  serializeJson(doc, jsonString);

  imuChar->setValue(jsonString.c_str());
  imuChar->notify();
  
  Serial.print("IMU: ");
  Serial.println(jsonString);
}

void sendButtonData() {
  StaticJsonDocument<128> doc;
  
  doc["panic_button_status"] = panicButtonStatus;
  doc["timestamp"] = getISO8601Timestamp();

  String jsonString;
  serializeJson(doc, jsonString);

  buttonChar->setValue(jsonString.c_str());
  buttonChar->notify();
  
  Serial.print("Button: ");
  Serial.println(jsonString);
}

void updateSensorValues() {
  // Simulate heart rate variation (70-80 bpm)
  static float heartRatePhase = 0;
  heartRatePhase += 0.1;
  heartRateValue = 75.0 + 5.0 * sin(heartRatePhase);

  // Simulate accelerometer movement
  static float accelPhase = 0;
  accelPhase += 0.05;
  accelX = 0.1 * sin(accelPhase);
  accelY = 0.2 * cos(accelPhase);
  accelZ = 9.8 + 0.1 * sin(accelPhase * 2);

  // Simulate gyroscope rotation
  static float gyroPhase = 0;
  gyroPhase += 0.03;
  gyroX = 0.01 * sin(gyroPhase);
  gyroY = 0.02 * cos(gyroPhase);
  gyroZ = 0.03 * sin(gyroPhase * 1.5);

  // Simulate button press (toggle every 10 seconds)
  static unsigned long lastButtonToggle = 0;
  if (millis() - lastButtonToggle > 10000) {
    panicButtonStatus = !panicButtonStatus;
    lastButtonToggle = millis();
  }
}

String getISO8601Timestamp() {
  // Simple timestamp format (in real device, use RTC)
  unsigned long seconds = millis() / 1000;
  char timestamp[32];
  sprintf(timestamp, "2025-12-29T%02lu:%02lu:%02luZ", 
          (seconds / 3600) % 24, 
          (seconds / 60) % 60, 
          seconds % 60);
  return String(timestamp);
}
