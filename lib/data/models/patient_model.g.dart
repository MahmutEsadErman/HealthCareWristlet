// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'patient_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Patient _$PatientFromJson(Map<String, dynamic> json) => Patient(
  id: (json['id'] as num).toInt(),
  userId: (json['user_id'] as num).toInt(),
  username: json['username'] as String,
  minHr: (json['min_hr'] as num).toInt(),
  maxHr: (json['max_hr'] as num).toInt(),
  inactivityLimitMinutes: (json['inactivity_limit_minutes'] as num).toInt(),
);

Map<String, dynamic> _$PatientToJson(Patient instance) => <String, dynamic>{
  'id': instance.id,
  'user_id': instance.userId,
  'username': instance.username,
  'min_hr': instance.minHr,
  'max_hr': instance.maxHr,
  'inactivity_limit_minutes': instance.inactivityLimitMinutes,
};

ThresholdUpdate _$ThresholdUpdateFromJson(Map<String, dynamic> json) =>
    ThresholdUpdate(
      minHr: (json['min_hr'] as num?)?.toInt(),
      maxHr: (json['max_hr'] as num?)?.toInt(),
      inactivityLimitMinutes: (json['inactivity_limit_minutes'] as num?)
          ?.toInt(),
    );

Map<String, dynamic> _$ThresholdUpdateToJson(ThresholdUpdate instance) =>
    <String, dynamic>{
      'min_hr': ?instance.minHr,
      'max_hr': ?instance.maxHr,
      'inactivity_limit_minutes': ?instance.inactivityLimitMinutes,
    };
