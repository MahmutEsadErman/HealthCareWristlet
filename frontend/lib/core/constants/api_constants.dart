import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConstants {
  static String get baseUrl =>
      dotenv.env['API_BASE_URL'] ??
      dotenv.env['HOME_BASE_URL'] ??
      'http://10.0.2.2:5000';

  // Auth Endpoints
  static const String authRegister = '/auth/register';
  static const String authLogin = '/auth/login';

  // Wearable Data Endpoints
  static const String wearableHeartRate = '/api/wearable/heart_rate';
  static const String wearableImu = '/api/wearable/imu';
  static const String wearableButton = '/api/wearable/button';
  static const String wearableFall = '/api/wearable/fall';
  static const String wearableInactivity = '/api/wearable/inactivity';

  // Patient & Alert Endpoints
  static const String alerts = '/api/alerts';
  static const String patients = '/api/patients';

  // Dynamic Endpoints
  static String patientThresholds(int patientUserId) => '/api/patients/$patientUserId/thresholds';
  static String alertResolve(int alertId) => '/api/alerts/$alertId/resolve';
}
