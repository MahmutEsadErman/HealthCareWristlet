import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/patient_model.dart';
import '../../data/repositories/patient_repository.dart';
import '../../core/errors/app_exception.dart';
import 'auth_provider.dart';

// PatientNotifier - Hasta listesini yöneten AsyncNotifier
class PatientNotifier extends AsyncNotifier<List<Patient>> {
  late final PatientRepository _repository;

  @override
  Future<List<Patient>> build() async {
    // Repository'yi al
    _repository = ref.read(patientRepositoryProvider);

    // İlk yüklemede hasta listesini getir
    return _loadPatients();
  }

  // Hasta listesini yükle
  Future<List<Patient>> _loadPatients() async {
    try {
      return await _repository.getPatients();
    } on AppException catch (e) {
      throw e.message;
    } catch (e) {
      throw 'Hasta listesi yüklenirken hata oluştu';
    }
  }

  // Hasta listesini yenile
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadPatients());
  }

  // Hasta eşiklerini güncelle
  Future<bool> updateThresholds({
    required int patientUserId,
    required ThresholdUpdate thresholds,
  }) async {
    try {
      await _repository.updateThresholds(patientUserId, thresholds);

      // Başarılı güncelleme sonrası listeyi yenile
      await refresh();
      return true;
    } on AppException catch (e) {
      // Hata durumunda state'i error olarak güncelle
      state = AsyncValue.error(e.message, StackTrace.current);
      return false;
    } catch (e) {
      state = AsyncValue.error(
        'Eşikler güncellenirken hata oluştu',
        StackTrace.current,
      );
      return false;
    }
  }

  // Belirli bir hastayı ID ile bul
  Patient? getPatientById(int userId) {
    return state.value?.firstWhere(
      (patient) => patient.userId == userId,
      orElse: () => throw 'Hasta bulunamadı',
    );
  }
}

// Provider tanımlamaları

// PatientRepository provider
final patientRepositoryProvider = Provider<PatientRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return PatientRepository(apiClient: apiClient);
});

// PatientNotifier provider
final patientProvider =
    AsyncNotifierProvider<PatientNotifier, List<Patient>>(() {
  return PatientNotifier();
});
