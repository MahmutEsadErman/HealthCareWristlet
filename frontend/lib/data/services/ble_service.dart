import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/sensor_data_model.dart';
import './api_client.dart';
import './notification_service.dart';

/// ESP32 Wristlet BLE Service
/// Manages Bluetooth connection and receives sensor data
class BleService {
  final Logger _logger = Logger();
  final ApiClient _apiClient;
  final NotificationService _notificationService = NotificationService();

  // Avoid log spam on frequent notifications
  static const Duration _sendErrorLogInterval = Duration(seconds: 30);
  DateTime? _lastHeartRateSendErrorLogAt;
  DateTime? _lastImuSendErrorLogAt;
  DateTime? _lastButtonSendErrorLogAt;

  StreamSubscription<List<ScanResult>>? _scanResultsSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  BleService(this._apiClient) {
    // NotificationService'i başlat
    _notificationService.initialize();
  }

  // UUIDs - Nordic UART Service (NUS) - ESP32-DUAL cihazı için
  static String get serviceUuid => dotenv.get('BLE_SERVICE_UUID', fallback: '6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
  static String get txCharUuid => dotenv.get('BLE_TX_CHAR_UUID', fallback: '6E400003-B5A3-F393-E0A9-E50E24DCCA9E'); // ESP32 -> Phone (NOTIFY)
  static String get rxCharUuid => dotenv.get('BLE_RX_CHAR_UUID', fallback: '6E400002-B5A3-F393-E0A9-E50E24DCCA9E'); // Phone -> ESP32 (WRITE)
  
  // Eski UUID'ler (uyumluluk için saklanıyor)
  static String get heartRateCharUuid => txCharUuid;
  static String get imuCharUuid => txCharUuid;
  static String get buttonCharUuid => txCharUuid;

  // Device name to search for
  static String get deviceName => dotenv.get('BLE_DEVICE_NAME', fallback: 'HealthCareWristlet');

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _txChar; // ESP32 -> Phone (NOTIFY)
  BluetoothCharacteristic? _rxChar; // Phone -> ESP32 (WRITE)
  
  // Eski değişkenler (uyumluluk için)
  BluetoothCharacteristic? _heartRateChar;
  BluetoothCharacteristic? _imuChar;
  BluetoothCharacteristic? _buttonChar;

  // Stream controllers for sensor data
  final _heartRateController = StreamController<HeartRateData>.broadcast();
  final _imuController = StreamController<IMUData>.broadcast();
  final _buttonController = StreamController<ButtonData>.broadcast();
  final _inactivityController = StreamController<InactivityData>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();

  // Public streams
  Stream<HeartRateData> get heartRateStream => _heartRateController.stream;
  Stream<IMUData> get imuStream => _imuController.stream;
  Stream<ButtonData> get buttonStream => _buttonController.stream;
  Stream<InactivityData> get inactivityStream => _inactivityController.stream;
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  bool get isConnected => _connectedDevice != null;

  /// Request Bluetooth permissions
  Future<bool> requestPermissions() async {
    try {
      _logger.i("Requesting Bluetooth permissions...");

      
      // Android 12+ permissions
      final bluetoothScan = await Permission.bluetoothScan.request();
      final bluetoothConnect = await Permission.bluetoothConnect.request();
      
      // Location permission (required for BLE scan on some devices)
      final location = await Permission.locationWhenInUse.request();

      // Location permission IS required for BLE scan on most Android devices
      // Even on Android 12+, many devices still require location for BLE scanning
      final bool granted = bluetoothScan.isGranted && bluetoothConnect.isGranted && location.isGranted;


      
      if (!granted) {
        _logger.w("Required permissions not granted");
        
        if (!location.isGranted) {
          _logger.e("LOCATION permission is REQUIRED for BLE scanning!");
        }
        
        if (bluetoothScan.isPermanentlyDenied || 
            bluetoothConnect.isPermanentlyDenied || 
            location.isPermanentlyDenied) {
          _logger.e("Permissions permanently denied. Please enable in Settings > Apps > healthcare_wristlet > Permissions");
        }

        return false;
      }
      
      return true;
    } catch (e) {
      _logger.e("Error requesting permissions: $e");
      return false;
    }
  }

  /// Start scanning for the wristlet device
  Future<void> startScanning() async {
    try {
      _logger.i("Starting BLE scan for $deviceName...");

      // Check if Bluetooth is available
      if (await FlutterBluePlus.isSupported == false) {
        _logger.e("Bluetooth not supported by this device");
        return;
      }

      // Check if Bluetooth is on
      try {
        final adapterState = await FlutterBluePlus.adapterState.first;
        _logger.i("Bluetooth adapter state: $adapterState");
        if (adapterState != BluetoothAdapterState.on) {
          _logger.e("Bluetooth is OFF. Please turn it on.");
          return;
        }
      } catch (e) {
        _logger.w("Could not check Bluetooth state: $e");
      }

      // Request permissions first
      final hasPermissions = await requestPermissions();
      if (!hasPermissions) {
        _logger.e("Cannot scan without permissions");
        return;
      }

      // Cancel any previous scan subscription to avoid multiple listeners
      await _scanResultsSub?.cancel();
      _scanResultsSub = null;

      // Start scanning with longer timeout
      // NOT: withServices filtresi bazı Android cihazlarda çalışmıyor
      // Bu yüzden tüm cihazları tarayıp manuel filtreleme yapıyoruz
      _logger.i("Starting scan with 20 second timeout...");
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 20),
        androidUsesFineLocation: true, // Bazı cihazlarda gerekli
      );

      // Listen to scan results
      _scanResultsSub = FlutterBluePlus.scanResults.listen((results) {
        _logger.i("Found ${results.length} devices");
        
        for (ScanResult result in results) {
          String deviceNameStr = result.device.platformName;
          String deviceId = result.device.remoteId.toString();
          final advName = result.advertisementData.advName;
          final localName = result.advertisementData.localName;
          final advServiceUuids = result.advertisementData.serviceUuids
              .map((e) => e.toString().toLowerCase())
              .toList();


          
          // İsim eşleşmesi - daha esnek kontrol (ESP32-DUAL veya HealthWristlet)
          final nameMatch = deviceNameStr.toLowerCase().contains(deviceName.toLowerCase()) ||
              advName.toLowerCase().contains(deviceName.toLowerCase()) ||
              localName.toLowerCase().contains(deviceName.toLowerCase()) ||
              deviceNameStr.toLowerCase().contains('esp32') ||
              advName.toLowerCase().contains('esp32') ||
              deviceNameStr.toLowerCase().contains('health') ||
              advName.toLowerCase().contains('health');
          
          final serviceMatch = advServiceUuids.contains(serviceUuid.toLowerCase());

          // İsim veya service UUID eşleşirse bağlan
          if (serviceMatch || nameMatch) {
            _logger.i("MATCH FOUND! Connecting to $deviceNameStr");
            stopScanning();
            connectToDevice(result.device);
            break;
          }
        }
      });
    } catch (e) {
      _logger.e("Error during scan: $e");
    }
  }

  /// Stop scanning
  Future<void> stopScanning() async {
    await FlutterBluePlus.stopScan();
    _logger.i("Stopped BLE scan");
  }

  /// Connect to the wristlet device
  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      _logger.i("Connecting to ${device.platformName} (${device.remoteId})...");

      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      _connectedDevice = device;
      _connectionStateController.add(true);
      _logger.i("Connected to ${device.platformName}");

      // Discover services
      await _discoverServices();

      // Listen to connection state changes
      await _connectionSub?.cancel();
      _connectionSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _logger.w("Device disconnected");
          _handleDisconnection();
        }
      });
    } catch (e) {
      _logger.e("Error connecting to device: $e");
      _connectionStateController.add(false);
    }
  }

  /// Discover services and setup characteristic notifications
  Future<void> _discoverServices() async {
    if (_connectedDevice == null) return;

    try {
      List<BluetoothService> services = await _connectedDevice!.discoverServices();

      for (BluetoothService service in services) {
        String svcUuid = service.uuid.toString().toLowerCase();
        _logger.i("Found service: $svcUuid");
        
        // Nordic UART Service (NUS) - ESP32-DUAL için
        if (svcUuid == serviceUuid.toLowerCase()) {
          _logger.i("Found ESP32-DUAL NUS service");

          for (BluetoothCharacteristic characteristic in service.characteristics) {
            String charUuid = characteristic.uuid.toString().toLowerCase();
            _logger.i("Found characteristic: $charUuid");

            // TX Characteristic (ESP32 -> Phone) - NOTIFY
            if (charUuid == txCharUuid.toLowerCase()) {
              _txChar = characteristic;
              _logger.i("Setting up TX characteristic for sensor data");
              await _setupCharacteristicNotification(
                characteristic,
                _onEsp32Data,
              );
            }
            // RX Characteristic (Phone -> ESP32) - WRITE
            else if (charUuid == rxCharUuid.toLowerCase()) {
              _rxChar = characteristic;
              _logger.i("Found RX characteristic for sending commands");
            }
          }
        }
      }

      _logger.i("All characteristics setup complete");
    } catch (e) {
      _logger.e("Error discovering services: $e");
    }
  }
  
  /// ESP32'den gelen CSV verisini işle
  /// Format: ax,ay,az,gx,gy,gz,rawIR,filteredSignal,threshold,bpm,finger
  /// veya: EVT,EMERGENCY
  void _onEsp32Data(List<int> data) async {
    try {
      String rawString = utf8.decode(data);
      _logger.i("Received: $rawString");

      // Fall event from ESP32 AI
      if (rawString.startsWith("ALARM,FALL")) {
        List<String> parts = rawString.split(',');
        double probability = 1.0;
        double? bpm;
        if (parts.length >= 3) {
          probability = double.tryParse(parts[2]) ?? 1.0;
        }
        if (parts.length >= 4) {
          bpm = double.tryParse(parts[3]);
        }

        final timestamp = DateTime.now().toIso8601String();

        // Local notification to patient device (optional UX)
        try {
          await _notificationService.showAlertNotification(
            id: DateTime.now().millisecondsSinceEpoch.remainder(1000000),
            title: 'Düşme algılandı',
            body: 'Skor: ${probability.toStringAsFixed(2)}'
                '${bpm != null ? ' • BPM: ${bpm.toStringAsFixed(1)}' : ''}',
          );
        } catch (_) {}

        // Send to backend so caregivers see FALL alert
        try {
          await _apiClient.sendFall(
            probability: probability,
            bpm: bpm,
            timestamp: timestamp,
          );
        } catch (e) {
          final now = DateTime.now();
          final last = _lastImuSendErrorLogAt; // reuse throttle window
          if (last == null || now.difference(last) >= _sendErrorLogInterval) {
            _lastImuSendErrorLogAt = now;
            _logger.w("Failed to send fall alert to server: $e");
          }
        }

        return;
      }
      
      // Emergency event kontrolü
      if (rawString.startsWith("EVT,EMERGENCY")) {
        _logger.w("EMERGENCY BUTTON PRESSED!");
        
        ButtonData button = ButtonData(
          panicButtonStatus: true,
          timestamp: DateTime.now().toIso8601String(),
        );
        _buttonController.add(button);
        
        // NOT: Hasta telefonunda bildirim gösterme!
        // Bildirim bakıcıya sunucu üzerinden gidecek (alert polling ile)
        
        // Sunucuya gönder - bakıcı bu alert'i görecek
        try {
          await _apiClient.sendPanicButton(button.timestamp);
          _logger.i("Emergency alert sent to server");
        } catch (e) {
          _logger.w("Failed to send panic button to server: $e");
        }
        return;
      }
      
      // Inactivity event kontrolü
      if (rawString.startsWith("EVT,INACTIVITY")) {
        _logger.w("INACTIVITY DETECTED!");
        
        InactivityData inactivity = InactivityData(
          isInactive: true,
          timestamp: DateTime.now().toIso8601String(),
        );
        _inactivityController.add(inactivity);
        
        // Sunucuya hareketsizlik alerti gönder
        try {
          await _apiClient.sendInactivityAlert(inactivity.timestamp!);
          _logger.i("Inactivity alert sent to server");
        } catch (e) {
          _logger.w("Failed to send inactivity alert to server: $e");
        }
        return;
      }
      
      // Yeni CSV sensor verisi formatı: bpm,finger,inactivity
      List<String> parts = rawString.split(',');
      if (parts.length >= 3) {
        double bpm = double.tryParse(parts[0]) ?? 0;
        int finger = int.tryParse(parts[1]) ?? 0;
        int inactivity = int.tryParse(parts[2]) ?? 0;
        
        String timestamp = DateTime.now().toIso8601String();
        
        // Hareketsizlik durumunu güncelle
        InactivityData inactivityData = InactivityData(
          isInactive: inactivity == 1,
          timestamp: timestamp,
        );
        _inactivityController.add(inactivityData);
        
        // Heart rate verisi (sadece parmak varsa)
        if (finger == 1 && bpm > 0) {
          HeartRateData heartRate = HeartRateData(
            value: bpm,
            timestamp: timestamp,
          );
          _heartRateController.add(heartRate);
          
          // Sunucuya gönder
          try {
            await _apiClient.sendHeartRate(bpm, timestamp);
          } catch (e) {
            final now = DateTime.now();
            final last = _lastHeartRateSendErrorLogAt;
            if (last == null || now.difference(last) >= _sendErrorLogInterval) {
              _lastHeartRateSendErrorLogAt = now;
              _logger.w("Failed to send heart rate to server: $e");
            }
          }
        }
        
        // NOT: Artık IMU verisi sürekli gönderilmiyor
        // Sadece hareketsizlik algılandığında EVT,INACTIVITY olarak geliyor
      }
    } catch (e) {
      _logger.e("Error parsing ESP32 data: $e");
    }
  }
  
  /// ESP32'ye threshold değeri gönder
  Future<void> sendThreshold(String key, double value) async {
    if (_rxChar == null) {
      _logger.w("RX characteristic not available");
      return;
    }
    
    try {
      String command = "THR,$key,$value";
      await _rxChar!.write(utf8.encode(command), withoutResponse: true);
      _logger.i("Sent threshold: $command");
    } catch (e) {
      _logger.e("Error sending threshold: $e");
    }
  }

  /// Setup notification for a characteristic
  Future<void> _setupCharacteristicNotification(
    BluetoothCharacteristic characteristic,
    Function(List<int>) onData,
  ) async {
    try {
      _logger.i("Setting up notifications for ${characteristic.uuid}...");
      
      await characteristic.setNotifyValue(true);
      _logger.i("setNotifyValue(true) completed for ${characteristic.uuid}");
      
      characteristic.lastValueStream.listen(
        (value) {
          _logger.i("Received ${value.length} bytes from ${characteristic.uuid}");
          if (value.isNotEmpty) {
            onData(value);
          }
        },
        onError: (error) {
          _logger.e("Stream error for ${characteristic.uuid}: $error");
        },
        onDone: () {
          _logger.w("Stream closed for ${characteristic.uuid}");
        },
        cancelOnError: false,
      );
      _logger.i("Notifications enabled for ${characteristic.uuid}");
    } catch (e, stackTrace) {
      _logger.e("Error setting up notifications: $e\n$stackTrace");
    }
  }

  /// Handle heart rate data
  void _onHeartRateData(List<int> data) async {
    try {
      String jsonString = utf8.decode(data);
      Map<String, dynamic> json = jsonDecode(jsonString);
      HeartRateData heartRate = HeartRateData.fromJson(json);
      _heartRateController.add(heartRate);
      
      // Send to server automatically
      try {
        await _apiClient.sendHeartRate(heartRate.value, heartRate.timestamp);
      } catch (e) {
        final now = DateTime.now();
        final last = _lastHeartRateSendErrorLogAt;
        if (last == null || now.difference(last) >= _sendErrorLogInterval) {
          _lastHeartRateSendErrorLogAt = now;
          _logger.w("Failed to send heart rate to server: $e");
        }
      }
    } catch (e) {
      _logger.e("Error parsing heart rate data: $e");
    }
  }

  /// Handle IMU data
  void _onIMUData(List<int> data) async {
    try {
      String jsonString = utf8.decode(data);
      Map<String, dynamic> json = jsonDecode(jsonString);
      IMUData imu = IMUData.fromJson(json);
      _imuController.add(imu);
      
      // Send to server automatically
      try {
        await _apiClient.sendIMU(
          imu.xAxis, imu.yAxis, imu.zAxis,
          imu.gx, imu.gy, imu.gz,
          imu.timestamp,
        );
      } catch (e) {
        final now = DateTime.now();
        final last = _lastImuSendErrorLogAt;
        if (last == null || now.difference(last) >= _sendErrorLogInterval) {
          _lastImuSendErrorLogAt = now;
          _logger.w("Failed to send IMU to server: $e");
        }
      }
    } catch (e) {
      _logger.e("Error parsing IMU data: $e");
    }
  }

  /// Handle button data
  void _onButtonData(List<int> data) async {
    try {
      String jsonString = utf8.decode(data);
      Map<String, dynamic> json = jsonDecode(jsonString);
      ButtonData button = ButtonData.fromJson(json);
      _buttonController.add(button);
      
      // Send to server automatically (only when pressed)
      if (button.panicButtonStatus) {
        try {
          await _apiClient.sendPanicButton(button.timestamp);
        } catch (e) {
          final now = DateTime.now();
          final last = _lastButtonSendErrorLogAt;
          if (last == null || now.difference(last) >= _sendErrorLogInterval) {
            _lastButtonSendErrorLogAt = now;
            _logger.w("Failed to send button status to server: $e");
          }
        }
      }
    } catch (e) {
      _logger.e("Error parsing button data: $e");
    }
  }

  /// Handle disconnection
  void _handleDisconnection() {
    _connectedDevice = null;
    _txChar = null;
    _rxChar = null;
    _heartRateChar = null;
    _imuChar = null;
    _buttonChar = null;
    _connectionStateController.add(false);
  }

  /// Disconnect from device
  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _handleDisconnection();
      _logger.i("Disconnected from device");
    }
  }

  /// Dispose resources
  void dispose() {
    _scanResultsSub?.cancel();
    _connectionSub?.cancel();
    _heartRateController.close();
    _imuController.close();
    _buttonController.close();
    _inactivityController.close();
    _connectionStateController.close();
    disconnect();
  }
}
