class AppConstants {
  // Polling
  static const int pollingInterval = 30; // seconds

  // Network
  static const int requestTimeout = 30; // seconds
  static const int connectTimeout = 30; // seconds
  static const int receiveTimeout = 30; // seconds

  // Storage Keys
  static const String tokenKey = 'jwt_token';
  static const String userIdKey = 'user_id';
  static const String userTypeKey = 'user_type';
  static const String usernameKey = 'username';

  // User Types
  static const String userTypePatient = 'patient';
  static const String userTypeCaregiver = 'caregiver';

  // Alert Types
  static const String alertTypeFall = 'FALL';
  static const String alertTypeInactivity = 'INACTIVITY';
  static const String alertTypeHrHigh = 'HR_HIGH';
  static const String alertTypeHrLow = 'HR_LOW';
  static const String alertTypeButton = 'BUTTON';
}
