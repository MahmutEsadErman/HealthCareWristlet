import 'package:json_annotation/json_annotation.dart';

part 'patient_model.g.dart';

@JsonSerializable()
class Patient {
  final int id;
  @JsonKey(name: 'user_id')
  final int userId;
  final String username; // Backend'den geliyor
  @JsonKey(name: 'min_hr')
  final int minHr;
  @JsonKey(name: 'max_hr')
  final int maxHr;
  @JsonKey(name: 'inactivity_limit_minutes')
  final int inactivityLimitMinutes;

  Patient({
    required this.id,
    required this.userId,
    required this.username,
    required this.minHr,
    required this.maxHr,
    required this.inactivityLimitMinutes,
  });

  factory Patient.fromJson(Map<String, dynamic> json) =>
      _$PatientFromJson(json);
  Map<String, dynamic> toJson() => _$PatientToJson(this);

  Patient copyWith({
    int? id,
    int? userId,
    String? username,
    int? minHr,
    int? maxHr,
    int? inactivityLimitMinutes,
  }) {
    return Patient(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      minHr: minHr ?? this.minHr,
      maxHr: maxHr ?? this.maxHr,
      inactivityLimitMinutes:
          inactivityLimitMinutes ?? this.inactivityLimitMinutes,
    );
  }
}

@JsonSerializable(includeIfNull: false)
class ThresholdUpdate {
  @JsonKey(name: 'min_hr')
  final int? minHr;
  @JsonKey(name: 'max_hr')
  final int? maxHr;
  @JsonKey(name: 'inactivity_limit_minutes')
  final int? inactivityLimitMinutes;

  ThresholdUpdate({
    this.minHr,
    this.maxHr,
    this.inactivityLimitMinutes,
  });

  factory ThresholdUpdate.fromJson(Map<String, dynamic> json) =>
      _$ThresholdUpdateFromJson(json);
  Map<String, dynamic> toJson() => _$ThresholdUpdateToJson(this);
}
