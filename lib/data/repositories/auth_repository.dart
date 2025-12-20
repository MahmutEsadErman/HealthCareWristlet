import '../models/user_model.dart';
import '../services/api_client.dart';
import '../../core/constants/api_constants.dart';

class AuthRepository {
  final ApiClient _apiClient;

  AuthRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Login - Username ve password ile giriş yap
  /// Backend: POST /auth/login
  /// Response: {access_token, user_type, user_id}
  Future<LoginResponse> login(String username, String password) async {
    final response = await _apiClient.post(
      ApiConstants.authLogin,
      data: {
        'username': username,
        'password': password,
      },
    );

    return LoginResponse.fromJson(response.data);
  }

  /// Register - Yeni kullanıcı kaydı
  /// Backend: POST /auth/register
  /// Request: {username, password, user_type}
  /// Response: {message, user_id}
  Future<RegisterResponse> register({
    required String username,
    required String password,
    required String userType, // 'patient' or 'caregiver'
  }) async {
    final response = await _apiClient.post(
      ApiConstants.authRegister,
      data: {
        'username': username,
        'password': password,
        'user_type': userType,
      },
    );

    return RegisterResponse.fromJson(response.data);
  }
}
