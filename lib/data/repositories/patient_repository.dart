import '../models/patient_model.dart';
import '../services/api_client.dart';
import '../../core/constants/api_constants.dart';

class PatientRepository {
  final ApiClient _apiClient;

  PatientRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Hasta listesini getir (Caregiver only)
  /// Backend: GET /api/patients
  /// Response: [{id, user_id, username, min_hr, max_hr, inactivity_limit_minutes}]
  Future<List<Patient>> getPatients() async {
    final response = await _apiClient.get(ApiConstants.patients);

    final List<dynamic> data = response.data;
    return data.map((json) => Patient.fromJson(json)).toList();
  }

  /// Hasta eşik değerlerini güncelle
  /// Backend: PUT /api/patients/{patient_user_id}/thresholds
  /// Request: {min_hr?, max_hr?, inactivity_limit_minutes?}
  /// Response: {message, patient}
  Future<void> updateThresholds(
    int patientUserId,
    ThresholdUpdate thresholdUpdate,
  ) async {
    await _apiClient.put(
      ApiConstants.patientThresholds(patientUserId),
      data: thresholdUpdate.toJson(),
    );
  }
}
