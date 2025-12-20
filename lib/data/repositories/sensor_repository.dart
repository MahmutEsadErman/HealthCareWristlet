import '../models/sensor_data_model.dart';
import '../services/api_client.dart';
import '../../core/constants/api_constants.dart';

class SensorRepository {
  final ApiClient _apiClient;

  SensorRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Kalp hızı verisi gönder (Patient only)
  /// Backend: POST /api/wearable/heart_rate
  /// Request: {value, timestamp?}
  /// Response: {message}
  /// Not: Backend eşik kontrolü yapar ve gerekirse alarm oluşturur
  Future<void> sendHeartRate(HeartRateData data) async {
    await _apiClient.post(
      ApiConstants.wearableHeartRate,
      data: data.toJson(),
    );
  }

  /// IMU (İvmeölçer + Jiroskop) verisi gönder (Patient only)
  /// Backend: POST /api/wearable/imu
  /// Request: {x_axis, y_axis, z_axis, gx?, gy?, gz?, timestamp?}
  /// Response: {message}
  /// Not: Backend hareketsizlik kontrolü yapar
  Future<void> sendIMU(IMUData data) async {
    await _apiClient.post(
      ApiConstants.wearableImu,
      data: data.toJson(),
    );
  }

  /// Panik butonu durumu gönder (Patient only)
  /// Backend: POST /api/wearable/button
  /// Request: {panic_button_status, timestamp?}
  /// Response: {message}
  /// Not: true gönderildiğinde anında BUTTON alarmı oluşturulur
  Future<void> sendButton(ButtonData data) async {
    await _apiClient.post(
      ApiConstants.wearableButton,
      data: data.toJson(),
    );
  }
}
