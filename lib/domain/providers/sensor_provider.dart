import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/sensor_data_model.dart';
import '../../data/repositories/sensor_repository.dart';
import '../../core/errors/app_exception.dart';
import 'auth_provider.dart';

// SensorState - Sensör veri gönderme durumu
class SensorState {
  final bool isLoading;
  final String? lastResponse;
  final String? error;
  final SensorType? lastSentType;

  SensorState({
    this.isLoading = false,
    this.lastResponse,
    this.error,
    this.lastSentType,
  });

  SensorState copyWith({
    bool? isLoading,
    String? lastResponse,
    String? error,
    SensorType? lastSentType,
  }) {
    return SensorState(
      isLoading: isLoading ?? this.isLoading,
      lastResponse: lastResponse,
      error: error,
      lastSentType: lastSentType ?? this.lastSentType,
    );
  }

  factory SensorState.initial() => SensorState();

  factory SensorState.loading(SensorType type) => SensorState(
        isLoading: true,
        lastSentType: type,
      );

  factory SensorState.success(String message, SensorType type) => SensorState(
        lastResponse: message,
        lastSentType: type,
      );

  factory SensorState.error(String message) => SensorState(error: message);
}

// Sensör tipleri
enum SensorType {
  heartRate,
  imu,
  button,
}

// SensorNotifier - Sensör verilerini gönderen StateNotifier
class SensorNotifier extends StateNotifier<SensorState> {
  final SensorRepository _repository;

  SensorNotifier(this._repository) : super(SensorState.initial());

  // Kalp hızı verisi gönder
  Future<bool> sendHeartRate(int heartRate) async {
    state = SensorState.loading(SensorType.heartRate);

    try {
      final data = HeartRateData(
        value: heartRate.toDouble(),
        timestamp: DateTime.now().toIso8601String(),
      );

      await _repository.sendHeartRate(data);

      state = SensorState.success(
        'Kalp hızı gönderildi: $heartRate bpm',
        SensorType.heartRate,
      );
      return true;
    } on AppException catch (e) {
      state = SensorState.error(e.message);
      return false;
    } catch (e) {
      state = SensorState.error('Kalp hızı gönderilirken hata oluştu');
      return false;
    }
  }

  // IMU (ivmeölçer) verisi gönder
  Future<bool> sendIMU({
    required double xAxis,
    required double yAxis,
    required double zAxis,
    double? gx,
    double? gy,
    double? gz,
  }) async {
    state = SensorState.loading(SensorType.imu);

    try {
      final data = IMUData(
        xAxis: xAxis,
        yAxis: yAxis,
        zAxis: zAxis,
        gx: gx,
        gy: gy,
        gz: gz,
        timestamp: DateTime.now().toIso8601String(),
      );

      await _repository.sendIMU(data);

      state = SensorState.success(
        'IMU verisi gönderildi: ($xAxis, $yAxis, $zAxis)',
        SensorType.imu,
      );
      return true;
    } on AppException catch (e) {
      state = SensorState.error(e.message);
      return false;
    } catch (e) {
      state = SensorState.error('IMU verisi gönderilirken hata oluştu');
      return false;
    }
  }

  // Panik butonu verisi gönder
  Future<bool> sendButton({required bool panicButtonStatus}) async {
    state = SensorState.loading(SensorType.button);

    try {
      final data = ButtonData(
        panicButtonStatus: panicButtonStatus,
        timestamp: DateTime.now().toIso8601String(),
      );

      await _repository.sendButton(data);

      state = SensorState.success(
        'Panik butonu gönderildi: ${panicButtonStatus ? "Basıldı" : "Bırakıldı"}',
        SensorType.button,
      );
      return true;
    } on AppException catch (e) {
      state = SensorState.error(e.message);
      return false;
    } catch (e) {
      state = SensorState.error('Buton verisi gönderilirken hata oluştu');
      return false;
    }
  }

  // Test senaryoları

  // Yüksek kalp hızı testi (alarm tetiklemeli)
  Future<bool> sendHighHeartRate() async {
    return await sendHeartRate(150); // > 120 (default max_hr)
  }

  // Düşük kalp hızı testi (alarm tetiklemeli)
  Future<bool> sendLowHeartRate() async {
    return await sendHeartRate(30); // < 40 (default min_hr)
  }

  // Normal kalp hızı testi
  Future<bool> sendNormalHeartRate() async {
    return await sendHeartRate(75); // Normal aralık
  }

  // Hareketsizlik testi (0 ivme - alarm için 30dk gerekli)
  Future<bool> sendInactivityData() async {
    return await sendIMU(
      xAxis: 0.0,
      yAxis: 0.0,
      zAxis: 0.0,
    );
  }

  // Düşme testi (yüksek ivme)
  Future<bool> sendFallData() async {
    return await sendIMU(
      xAxis: 15.0,
      yAxis: 5.0,
      zAxis: 20.0,
    );
  }

  // Normal hareket testi
  Future<bool> sendNormalMovement() async {
    return await sendIMU(
      xAxis: 1.5,
      yAxis: 0.8,
      zAxis: 9.8, // Gravity
    );
  }

  // Panik butonu testi
  Future<bool> sendPanicButton() async {
    return await sendButton(panicButtonStatus: true);
  }

  // Hata mesajını temizle
  void clearError() {
    if (state.error != null) {
      state = SensorState.initial();
    }
  }

  // Başarı mesajını temizle
  void clearSuccess() {
    if (state.lastResponse != null) {
      state = SensorState.initial();
    }
  }
}

// Provider tanımlamaları

// SensorRepository provider
final sensorRepositoryProvider = Provider<SensorRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return SensorRepository(apiClient: apiClient);
});

// SensorNotifier provider
final sensorProvider = StateNotifierProvider<SensorNotifier, SensorState>((ref) {
  final repository = ref.watch(sensorRepositoryProvider);
  return SensorNotifier(repository);
});
