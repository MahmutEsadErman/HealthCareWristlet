import 'package:dio/dio.dart';

class AppException implements Exception {
  final String message;
  final int? statusCode;

  AppException(this.message, [this.statusCode]);

  factory AppException.fromDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return AppException('Bağlantı zaman aşımına uğradı', 408);

      case DioExceptionType.sendTimeout:
        return AppException('İstek gönderilirken zaman aşımı', 408);

      case DioExceptionType.receiveTimeout:
        return AppException('Yanıt alınırken zaman aşımı', 408);

      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        final data = error.response?.data;

        String message = 'Sunucu hatası';
        if (data is Map<String, dynamic> && data.containsKey('message')) {
          message = data['message'];
        }

        switch (statusCode) {
          case 400:
            return AppException(message, 400);
          case 401:
            return AppException('Oturum süreniz doldu. Lütfen tekrar giriş yapın.', 401);
          case 403:
            return AppException('Bu işlem için yetkiniz yok.', 403);
          case 404:
            return AppException('İstenilen kaynak bulunamadı.', 404);
          case 500:
          case 502:
          case 503:
            return AppException('Sunucu hatası. Lütfen daha sonra tekrar deneyin.', statusCode);
          default:
            return AppException(message, statusCode);
        }

      case DioExceptionType.cancel:
        return AppException('İstek iptal edildi');

      case DioExceptionType.badCertificate:
        return AppException('Güvenlik sertifikası hatası');

      case DioExceptionType.connectionError:
        return AppException('İnternet bağlantısı yok. Lütfen bağlantınızı kontrol edin.');

      case DioExceptionType.unknown:
      default:
        if (error.message?.contains('SocketException') ?? false) {
          return AppException('Sunucuya bağlanılamıyor. Lütfen internet bağlantınızı kontrol edin.');
        }
        return AppException('Bilinmeyen bir hata oluştu.');
    }
  }

  @override
  String toString() => message;
}
