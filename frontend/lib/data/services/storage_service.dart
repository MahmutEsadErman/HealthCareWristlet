import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants/app_constants.dart';

class StorageService {
  final FlutterSecureStorage _storage;

  StorageService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  // Token Management
  Future<void> saveToken(String token) async {
    await _storage.write(key: AppConstants.tokenKey, value: token);
  }

  Future<String?> getToken() async {
    return await _storage.read(key: AppConstants.tokenKey);
  }

  Future<void> deleteToken() async {
    await _storage.delete(key: AppConstants.tokenKey);
  }

  // User Info Management
  Future<void> saveUserInfo({
    required int userId,
    required String userType,
    required String username,
  }) async {
    await Future.wait([
      _storage.write(key: AppConstants.userIdKey, value: userId.toString()),
      _storage.write(key: AppConstants.userTypeKey, value: userType),
      _storage.write(key: AppConstants.usernameKey, value: username),
    ]);
  }

  Future<Map<String, String?>> getUserInfo() async {
    final results = await Future.wait([
      _storage.read(key: AppConstants.userIdKey),
      _storage.read(key: AppConstants.userTypeKey),
      _storage.read(key: AppConstants.usernameKey),
    ]);

    return {
      'user_id': results[0],
      'user_type': results[1],
      'username': results[2],
    };
  }

  Future<int?> getUserId() async {
    final userIdStr = await _storage.read(key: AppConstants.userIdKey);
    return userIdStr != null ? int.tryParse(userIdStr) : null;
  }

  Future<String?> getUserType() async {
    return await _storage.read(key: AppConstants.userTypeKey);
  }

  Future<String?> getUsername() async {
    return await _storage.read(key: AppConstants.usernameKey);
  }

  // Individual save methods
  Future<void> saveUserId(int userId) async {
    await _storage.write(key: AppConstants.userIdKey, value: userId.toString());
  }

  Future<void> saveUserType(String userType) async {
    await _storage.write(key: AppConstants.userTypeKey, value: userType);
  }

  Future<void> saveUsername(String username) async {
    await _storage.write(key: AppConstants.usernameKey, value: username);
  }

  // Clear All Data
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  // Check if user is logged in
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // API Base URL Management
  Future<void> saveApiUrl(String url) async {
    await _storage.write(key: 'api_base_url', value: url);
  }

  Future<String?> getApiUrl() async {
    return await _storage.read(key: 'api_base_url');
  }

  Future<void> deleteApiUrl() async {
    await _storage.delete(key: 'api_base_url');
  }
}
