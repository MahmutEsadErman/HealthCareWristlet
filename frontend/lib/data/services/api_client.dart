import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../../core/constants/api_constants.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import 'storage_service.dart';

class ApiClient {
  final Dio _dio;
  final StorageService _storageService;
  final Logger _logger;

  bool _isWearablePath(String path) {
    // High-frequency endpoints: avoid spamming logs for every packet.
    return path.startsWith('/api/wearable') ||
        path == ApiConstants.wearableHeartRate ||
        path == ApiConstants.wearableImu ||
        path == ApiConstants.wearableButton;
  }

  ApiClient({
    required StorageService storageService,
    Dio? dio,
    Logger? logger,
  })  : _storageService = storageService,
        _logger = logger ?? Logger(),
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: ApiConstants.baseUrl,
                connectTimeout: Duration(seconds: AppConstants.connectTimeout),
                receiveTimeout: Duration(seconds: AppConstants.receiveTimeout),
                sendTimeout: Duration(seconds: AppConstants.requestTimeout),
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            ) {
    _setupInterceptors();
  }

  void _setupInterceptors() {
    // Auth Interceptor - JWT token ekleme
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Token'ı storage'dan al ve header'a ekle
          final token = await _storageService.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          if (!_isWearablePath(options.path)) {
            _logger.d('REQUEST[${options.method}] => PATH: ${options.path}');
            _logger.d('Headers: ${options.headers}');
            if (options.data != null) {
              _logger.d('Body: ${options.data}');
            }
          }

          return handler.next(options);
        },
        onResponse: (response, handler) {
          final path = response.requestOptions.path;
          if (!_isWearablePath(path)) {
            _logger.d('RESPONSE[${response.statusCode}] => PATH: $path');
            _logger.d('Data: ${response.data}');
          }
          return handler.next(response);
        },
        onError: (error, handler) async {
          _logger.e(
            'ERROR[${error.response?.statusCode}] => PATH: ${error.requestOptions.path}',
          );
          _logger.e('Message: ${error.message}');

          // 401 Unauthorized - Token expired veya geçersiz
          if (error.response?.statusCode == 401) {
            _logger.w('Token expired or invalid. Clearing storage...');
            await _storageService.clearAll();
            // NOT: Logout işlemi ve routing AuthProvider tarafından handle edilecek
          }

          return handler.next(error);
        },
      ),
    );
  }

  // Generic GET request
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
        options: options,
      );
      return response;
    } on DioException catch (e) {
      throw AppException.fromDioError(e);
    }
  }

  // Generic POST request
  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      return response;
    } on DioException catch (e) {
      throw AppException.fromDioError(e);
    }
  }

  // Generic PUT request
  Future<Response> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.put(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      return response;
    } on DioException catch (e) {
      throw AppException.fromDioError(e);
    }
  }

  // Generic DELETE request
  Future<Response> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.delete(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      return response;
    } on DioException catch (e) {
      throw AppException.fromDioError(e);
    }
  }

  // Wearable Data Methods
  
  /// Send heart rate data to server
  Future<Response> sendHeartRate(double value, String? timestamp) async {
    return await post(
      ApiConstants.wearableHeartRate,
      data: {
        'value': value,
        if (timestamp != null) 'timestamp': timestamp,
      },
    );
  }

  /// Send IMU (accelerometer + gyroscope) data to server
  Future<Response> sendIMU(
    double xAxis,
    double yAxis,
    double zAxis,
    double? gx,
    double? gy,
    double? gz,
    String? timestamp,
  ) async {
    return await post(
      ApiConstants.wearableImu,
      data: {
        'x_axis': xAxis,
        'y_axis': yAxis,
        'z_axis': zAxis,
        if (gx != null) 'gx': gx,
        if (gy != null) 'gy': gy,
        if (gz != null) 'gz': gz,
        if (timestamp != null) 'timestamp': timestamp,
      },
    );
  }

  /// Send panic button status to server
  Future<Response> sendPanicButton(String? timestamp) async {
    return await post(
      ApiConstants.wearableButton,
      data: {
        'panic_button_status': true,
        if (timestamp != null) 'timestamp': timestamp,
      },
    );
  }
}
