import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/services/storage_service.dart';
import '../../data/services/api_client.dart';
import '../../core/errors/app_exception.dart';

// AuthState - Kimlik doğrulama durumu
class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;
  final bool isAuthenticated;

  AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.isAuthenticated = false,
  });

  AuthState copyWith({
    User? user,
    bool? isLoading,
    String? error,
    bool? isAuthenticated,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    );
  }

  // Başlangıç durumu
  factory AuthState.initial() => AuthState();

  // Yükleniyor durumu
  factory AuthState.loading() => AuthState(isLoading: true);

  // Kimlik doğrulama başarılı
  factory AuthState.authenticated(User user) => AuthState(
        user: user,
        isAuthenticated: true,
      );

  // Hata durumu
  factory AuthState.error(String message) => AuthState(error: message);
}

// AuthNotifier - Kimlik doğrulama işlemlerini yöneten StateNotifier
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _authRepository;
  final StorageService _storageService;

  AuthNotifier(this._authRepository, this._storageService)
      : super(AuthState.initial()) {
    // Başlangıçta token kontrolü yap
    _checkAuthStatus();
  }

  // Token kontrolü - Uygulama başlatıldığında çağrılır
  Future<void> _checkAuthStatus() async {
    state = AuthState.loading();

    try {
      final isLoggedIn = await _storageService.isLoggedIn();

      if (isLoggedIn) {
        // Token varsa user bilgilerini storage'dan al
        final userId = await _storageService.getUserId();
        final username = await _storageService.getUsername();
        final userType = await _storageService.getUserType();

        if (userId != null && username != null && userType != null) {
          final user = User(
            id: userId,
            username: username,
            userType: userType,
          );
          state = AuthState.authenticated(user);
        } else {
          // Token var ama user bilgisi eksikse logout
          await logout();
        }
      } else {
        state = AuthState.initial();
      }
    } catch (e) {
      state = AuthState.initial();
    }
  }

  // Login işlemi
  Future<bool> login(String username, String password) async {
    state = AuthState.loading();

    try {
      final response = await _authRepository.login(username, password);

      // Token ve user bilgilerini kaydet
      await _storageService.saveToken(response.accessToken);
      await _storageService.saveUserId(response.userId);
      await _storageService.saveUserType(response.userType);
      await _storageService.saveUsername(username);

      // User nesnesini oluştur ve state'i güncelle
      final user = User(
        id: response.userId,
        username: username,
        userType: response.userType,
      );

      state = AuthState.authenticated(user);
      return true;
    } on AppException catch (e) {
      state = AuthState.error(e.message);
      return false;
    } catch (e) {
      state = AuthState.error('Beklenmeyen bir hata oluştu');
      return false;
    }
  }

  // Register işlemi
  Future<bool> register(
      String username, String password, String userType) async {
    state = AuthState.loading();

    try {
      final response = await _authRepository.register(
        username: username,
        password: password,
        userType: userType,
      );

      // Kayıt başarılı mesajını göster
      state = AuthState.initial();
      return true;
    } on AppException catch (e) {
      state = AuthState.error(e.message);
      return false;
    } catch (e) {
      state = AuthState.error('Beklenmeyen bir hata oluştu');
      return false;
    }
  }

  // Logout işlemi
  Future<void> logout() async {
    await _storageService.clearAll();
    state = AuthState.initial();
  }

  // Hata mesajını temizle
  void clearError() {
    if (state.error != null) {
      state = state.copyWith(error: null);
    }
  }
}

// Provider tanımlamaları

// StorageService provider
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

// ApiClient provider
final apiClientProvider = Provider<ApiClient>((ref) {
  final storageService = ref.watch(storageServiceProvider);
  return ApiClient(storageService: storageService);
});

// AuthRepository provider
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AuthRepository(apiClient: apiClient);
});

// AuthNotifier provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  final storageService = ref.watch(storageServiceProvider);
  return AuthNotifier(authRepository, storageService);
});
