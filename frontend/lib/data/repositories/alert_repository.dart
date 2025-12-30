import 'package:logger/logger.dart';
import '../models/alert_model.dart';
import '../services/api_client.dart';
import '../../core/constants/api_constants.dart';

class AlertRepository {
  final ApiClient _apiClient;
  final Logger _logger = Logger();

  AlertRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Alarmları getir
  /// Backend: GET /api/alerts
  /// - Caregiver: Tüm alarmları görür
  /// - Patient: Sadece kendi alarmlarını görür
  /// Response: [{id, user_id, type, message, timestamp, is_resolved}]
  Future<List<Alert>> getAlerts() async {
    final response = await _apiClient.get(ApiConstants.alerts);

    _logger.d('Raw alert response: ${response.data}');

    try {
      final List<dynamic> data = response.data;
      _logger.d('Alert count: ${data.length}');

      final alerts = <Alert>[];
      for (var i = 0; i < data.length; i++) {
        try {
          final json = data[i] as Map<String, dynamic>;
          _logger.d('Parsing alert $i: $json');
          final alert = Alert.fromJson(json);
          alerts.add(alert);
        } catch (e, stack) {
          _logger.e('Error parsing alert $i: $e');
          _logger.e('Stack: $stack');
          _logger.e('JSON: ${data[i]}');
        }
      }

      return alerts;
    } catch (e, stack) {
      _logger.e('Error in getAlerts: $e');
      _logger.e('Stack: $stack');
      rethrow;
    }
  }

  /// Alarmı çözüldü olarak işaretle
  /// Backend: PUT /api/alerts/{alert_id}/resolve
  /// Response: {message}
  Future<void> resolveAlert(int alertId) async {
    await _apiClient.put(ApiConstants.alertResolve(alertId));
  }
}
