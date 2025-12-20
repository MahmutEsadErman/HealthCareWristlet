// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'alert_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Alert _$AlertFromJson(Map<String, dynamic> json) => Alert(
  id: (json['id'] as num).toInt(),
  userId: (json['user_id'] as num).toInt(),
  type: json['type'] as String,
  message: json['message'] as String,
  timestamp: DateTime.parse(json['timestamp'] as String),
  isResolved: json['is_resolved'] as bool,
  resolvedAt: json['resolved_at'] == null
      ? null
      : DateTime.parse(json['resolved_at'] as String),
);

Map<String, dynamic> _$AlertToJson(Alert instance) => <String, dynamic>{
  'id': instance.id,
  'user_id': instance.userId,
  'type': instance.type,
  'message': instance.message,
  'timestamp': instance.timestamp.toIso8601String(),
  'is_resolved': instance.isResolved,
  'resolved_at': instance.resolvedAt?.toIso8601String(),
};
