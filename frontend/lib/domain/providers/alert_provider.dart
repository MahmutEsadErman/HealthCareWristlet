import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/alert_model.dart';
import '../../data/repositories/alert_repository.dart';
import '../../data/services/notification_service.dart';
import '../../core/errors/app_exception.dart';
import 'auth_provider.dart';
import 'patient_provider.dart';

// AlertNotifier - Alarm listesini yöneten AsyncNotifier
class AlertNotifier extends AsyncNotifier<List<Alert>> {
  late final AlertRepository _repository;
  final NotificationService _notificationService = NotificationService();
  Timer? _pollingTimer;
  int _lastAlertCount = 0;

  @override
  Future<List<Alert>> build() async {
    // Repository'yi al
    _repository = ref.read(alertRepositoryProvider);

    // Provider dispose edildiğinde timer'ı durdur
    ref.onDispose(() {
      _pollingTimer?.cancel();
    });

    // Auth state'i dinle ve caregiver ise polling başlat
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.isAuthenticated && next.user?.userType == 'caregiver') {
        // Caregiver login yaptı, polling'i başlat
        startPolling(interval: const Duration(seconds: 2));
      } else {
        // Logout oldu veya patient, polling'i durdur
        stopPolling();
      }
    });

    // İlk yüklemede caregiver ise polling başlat
    final authState = ref.read(authProvider);
    if (authState.isAuthenticated && authState.user?.userType == 'caregiver') {
      Future.microtask(() {
        startPolling(interval: const Duration(seconds: 2));
      });
    }

    // İlk yüklemede alarm listesini getir
    return _loadAlerts();
  }

  // Alarm listesini yükle
  Future<List<Alert>> _loadAlerts() async {
    try {
      final alerts = await _repository.getAlerts();
      // Tarihe göre sırala (en yeni önce)
      alerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return alerts;
    } on AppException catch (e) {
      throw e.message;
    } catch (e) {
      throw 'Alarmlar yüklenirken hata oluştu';
    }
  }

  // Alarm listesini yenile
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadAlerts());
  }

  // Polling başlat (30 saniye aralıklarla)
  void startPolling({Duration interval = const Duration(seconds: 30)}) {
    // Önceki timer varsa durdur
    _pollingTimer?.cancel();

    // Notification service'i başlat
    _notificationService.initialize();

    // İlk yüklemede alarm sayısını kaydet
    if (state.hasValue) {
      _lastAlertCount = state.value?.where((a) => !a.isResolved).length ?? 0;
    }

    // Yeni timer başlat
    _pollingTimer = Timer.periodic(interval, (_) async {
      // Sessizce yenile (loading state gösterme)
      try {
        final alerts = await _loadAlerts();
        final currentUnresolvedCount = alerts.where((a) => !a.isResolved).length;

        // Yeni alarm varsa bildirim göster
        if (currentUnresolvedCount > _lastAlertCount) {
          final newAlertsCount = currentUnresolvedCount - _lastAlertCount;
          final latestAlert = alerts.firstWhere((a) => !a.isResolved);

          // Hasta adını bul
          String patientName = 'Hasta #${latestAlert.patientId}';
          try {
            final patientState = ref.read(patientProvider);
            if (patientState.hasValue && patientState.value != null) {
              final patients = patientState.value!;
              try {
                final patient = patients.firstWhere(
                  (p) => p.userId == latestAlert.patientId,
                );
                patientName = patient.username;
              } catch (e) {
                // Patient bulunamazsa ID göster
              }
            }
          } catch (e) {
            // Hata durumunda ID göster
          }

          await _notificationService.showAlertNotification(
            id: latestAlert.id,
            title: '🚨 Yeni Sağlık Alarmı!',
            body: '${latestAlert.getTypeTitle()} - $patientName',
            payload: 'alert_${latestAlert.id}',
          );
        }

        _lastAlertCount = currentUnresolvedCount;
        state = AsyncValue.data(alerts);
      } catch (e, stack) {
        // Polling sırasında hata olursa state'i güncelleme
        // Eski veriyi koru
      }
    });
  }

  // Polling durdur
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  // Alarmı çöz
  Future<bool> resolveAlert(int alertId) async {
    try {
      await _repository.resolveAlert(alertId);

      // Başarılı çözümleme sonrası listeyi yenile
      await refresh();
      return true;
    } on AppException catch (e) {
      // Hata durumunda state'i error olarak güncelle
      state = AsyncValue.error(e.message, StackTrace.current);
      return false;
    } catch (e) {
      state = AsyncValue.error(
        'Alarm çözümlenirken hata oluştu',
        StackTrace.current,
      );
      return false;
    }
  }

  // Çözülmemiş alarm sayısı
  int get unresolvedCount {
    final alerts = state.value ?? [];
    return alerts.where((alert) => !alert.isResolved).length;
  }

  // Sadece çözülmemiş alarmları getir
  List<Alert> get unresolvedAlerts {
    final alerts = state.value ?? [];
    return alerts.where((alert) => !alert.isResolved).toList();
  }

  // Belirli bir hasta için alarmları getir (Caregiver için)
  List<Alert> getAlertsForPatient(int patientId) {
    final alerts = state.value ?? [];
    return alerts.where((alert) => alert.patientId == patientId).toList();
  }
}

// Provider tanımlamaları

// AlertRepository provider
final alertRepositoryProvider = Provider<AlertRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AlertRepository(apiClient: apiClient);
});

// AlertNotifier provider
final alertProvider = AsyncNotifierProvider<AlertNotifier, List<Alert>>(() {
  return AlertNotifier();
});

// Çözülmemiş alarm sayısı için computed provider
final unresolvedAlertCountProvider = Provider<int>((ref) {
  final alertState = ref.watch(alertProvider);
  return alertState.when(
    data: (alerts) => alerts.where((a) => !a.isResolved).length,
    loading: () => 0,
    error: (_, __) => 0,
  );
});
