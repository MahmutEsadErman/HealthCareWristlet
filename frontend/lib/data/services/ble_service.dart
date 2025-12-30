import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/sensor_data_model.dart';
import './api_client.dart';

/// ESP32 Wristlet BLE Service
/// Manages Bluetooth connection and receives sensor data
class BleService {
  final Logger _logger = Logger();
  final ApiClient _apiClient;

  // Avoid log spam on frequent notifications
  static const Duration _sendErrorLogInterval = Duration(seconds: 30);
  DateTime? _lastHeartRateSendErrorLogAt;
  DateTime? _lastImuSendErrorLogAt;
  DateTime? _lastButtonSendErrorLogAt;

  StreamSubscription<List<ScanResult>>? _scanResultsSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  BleService(this._apiClient);

  // UUIDs - Read from .env file
  static String get serviceUuid => dotenv.get('BLE_SERVICE_UUID', fallback: '4fafc201-1fb5-459e-8fcc-c5c9c331914b');
  static String get heartRateCharUuid => dotenv.get('BLE_HEART_RATE_CHAR_UUID', fallback: 'beb5483e-36e1-4688-b7f5-ea07361b26a8');
  static String get imuCharUuid => dotenv.get('BLE_IMU_CHAR_UUID', fallback: 'beb5483f-36e1-4688-b7f5-ea07361b26a8');
  static String get buttonCharUuid => dotenv.get('BLE_BUTTON_CHAR_UUID', fallback: 'beb54840-36e1-4688-b7f5-ea07361b26a8');

  // Device name to search for
  static String get deviceName => dotenv.get('BLE_DEVICE_NAME', fallback: 'HealthWristlet');

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _heartRateChar;
  BluetoothCharacteristic? _imuChar;
  BluetoothCharacteristic? _buttonChar;

  // Stream controllers for sensor data
  final _heartRateController = StreamController<HeartRateData>.broadcast();
  final _imuController = StreamController<IMUData>.broadcast();
  final _buttonController = StreamController<ButtonData>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();

  // Public streams
  Stream<HeartRateData> get heartRateStream => _heartRateController.stream;
  Stream<IMUData> get imuStream => _imuController.stream;
  Stream<ButtonData> get buttonStream => _buttonController.stream;
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  bool get isConnected => _connectedDevice != null;

  /// Request Bluetooth permissions
  Future<bool> requestPermissions() async {
    try {
      _logger.i("Requesting Bluetooth permissions...");
      developer.log('requestPermissions() called', name: 'BLE');
      // ignore: avoid_print
      print('🔍 BLE: requestPermissions() called');
      
      // Android 12+ permissions
      final bluetoothScan = await Permission.bluetoothScan.request();
      final bluetoothConnect = await Permission.bluetoothConnect.request();
      
      // Location permission (required for BLE scan on some devices)
      final location = await Permission.locationWhenInUse.request();

      // On Android 12+ (API 31+), location is typically NOT required for BLE scan.
      // Some OEMs / older Android versions still behave better with location granted,
      // but we should not hard-block scanning if location is denied.
      final bool granted = bluetoothScan.isGranted && bluetoothConnect.isGranted;

      developer.log(
        'Permissions: scan=$bluetoothScan connect=$bluetoothConnect location=$location',
        name: 'BLE',
      );
      // ignore: avoid_print
      print('🔍 BLE: perms scan=$bluetoothScan connect=$bluetoothConnect location=$location');
      
      if (!granted) {
        _logger.w("Bluetooth permissions not granted");
        if (bluetoothScan.isPermanentlyDenied || 
            bluetoothConnect.isPermanentlyDenied || 
            location.isPermanentlyDenied) {
          _logger.e("Permissions permanently denied. Please enable in settings.");
        }

        return false;
      }

      if (!location.isGranted) {
        _logger.w(
          "Location permission not granted. Scan may still work on Android 12+, but if you can't discover devices, enable Location permission + Location services.",
        );
      }
      
      return true;
    } catch (e) {
      _logger.e("Error requesting permissions: $e");
      return false;
    }
  }

  /// Start scanning for the wristlet device
  Future<void> startScanning() async {
    print('🔍 BLE: startScanning() called');
    try {
      developer.log('startScanning() called', name: 'BLE');
      _logger.i("Starting BLE scan for $deviceName...");
      print('🔍 BLE: Device name = $deviceName');
      developer.log('Device name = $deviceName serviceUuid=$serviceUuid', name: 'BLE');

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

      final targetService = Guid(serviceUuid);

      // Start scanning with longer timeout
      _logger.i("Starting scan with 20 second timeout...");
      developer.log('FlutterBluePlus.startScan() begin (20s, withServices)', name: 'BLE');
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 20),
        withServices: [targetService],
        androidUsesFineLocation: false,
      );

      // Listen to scan results
      _scanResultsSub = FlutterBluePlus.scanResults.listen((results) {
        _logger.i("Found ${results.length} devices");
        // ignore: avoid_print
        print('🔍 BLE: scanResults count=${results.length}');
        
        for (ScanResult result in results) {
          String deviceNameStr = result.device.platformName;
          String deviceId = result.device.remoteId.toString();
          final advName = result.advertisementData.advName;
          final advServiceUuids = result.advertisementData.serviceUuids
              .map((e) => e.toString().toLowerCase())
              .toList();

          _logger.i(
            "Device: platformName='$deviceNameStr' advName='$advName' (ID: $deviceId) services=$advServiceUuids",
          );
          
          final nameMatch = deviceNameStr.toLowerCase() == deviceName.toLowerCase() ||
              advName.toLowerCase() == deviceName.toLowerCase();
          final serviceMatch = advServiceUuids.contains(serviceUuid.toLowerCase());

          // Prefer matching by service UUID (most reliable)
          if (serviceMatch || nameMatch) {
            _logger.i(
              "✅ MATCH FOUND! serviceMatch=$serviceMatch nameMatch=$nameMatch -> Connecting to ID=$deviceId",
            );
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
        if (service.uuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
          _logger.i("Found wristlet service");

          for (BluetoothCharacteristic characteristic in service.characteristics) {
            String charUuid = characteristic.uuid.toString().toLowerCase();

            if (charUuid == heartRateCharUuid.toLowerCase()) {
              _heartRateChar = characteristic;
              await _setupCharacteristicNotification(
                characteristic,
                _onHeartRateData,
              );
            } else if (charUuid == imuCharUuid.toLowerCase()) {
              _imuChar = characteristic;
              await _setupCharacteristicNotification(
                characteristic,
                _onIMUData,
              );
            } else if (charUuid == buttonCharUuid.toLowerCase()) {
              _buttonChar = characteristic;
              await _setupCharacteristicNotification(
                characteristic,
                _onButtonData,
              );
            }
          }
        }
      }

      _logger.i("All characteristics setup complete");
    } catch (e) {
      _logger.e("Error discovering services: $e");
    }
  }

  /// Setup notification for a characteristic
  Future<void> _setupCharacteristicNotification(
    BluetoothCharacteristic characteristic,
    Function(List<int>) onData,
  ) async {
    try {
      await characteristic.setNotifyValue(true);
      characteristic.lastValueStream.listen((value) {
        if (value.isNotEmpty) {
          onData(value);
        }
      });
      _logger.i("Notifications enabled for ${characteristic.uuid}");
    } catch (e) {
      _logger.e("Error setting up notifications: $e");
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
    _connectionStateController.close();
    disconnect();
  }
}
