import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/ble_service.dart';
import '../../data/models/sensor_data_model.dart';
import 'auth_provider.dart';

/// BLE Service Provider
final bleServiceProvider = Provider<BleService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final service = BleService(apiClient);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Connection State Provider
final bleConnectionStateProvider = StreamProvider<bool>((ref) {
  final bleService = ref.watch(bleServiceProvider);
  // StreamProvider stays in `loading` until the first event arrives.
  // Emit an initial value so the UI can show the Scan button immediately.
  return (() async* {
    yield bleService.isConnected;
    yield* bleService.connectionStateStream;
  })();
});

/// Heart Rate Stream Provider
final heartRateStreamProvider = StreamProvider<HeartRateData>((ref) {
  final bleService = ref.watch(bleServiceProvider);
  return bleService.heartRateStream;
});

/// IMU Stream Provider
final imuStreamProvider = StreamProvider<IMUData>((ref) {
  final bleService = ref.watch(bleServiceProvider);
  return bleService.imuStream;
});

/// Button Stream Provider
final buttonStreamProvider = StreamProvider<ButtonData>((ref) {
  final bleService = ref.watch(bleServiceProvider);
  return bleService.buttonStream;
});

/// Inactivity Stream Provider
final inactivityStreamProvider = StreamProvider<InactivityData>((ref) {
  final bleService = ref.watch(bleServiceProvider);
  return bleService.inactivityStream;
});
