import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import '../../core/constants/app_constants.dart';

part 'alert_model.g.dart';

@JsonSerializable()
class Alert {
  final int id;
  @JsonKey(name: 'user_id')
  final int userId;

  // patient_id backend'de yok, user_id ile aynı
  @JsonKey(name: 'patient_id', includeFromJson: false, includeToJson: false)
  int get patientId => userId;

  final String type; // FALL, INACTIVITY, HR_HIGH, HR_LOW, BUTTON
  final String message;
  final DateTime timestamp;
  @JsonKey(name: 'is_resolved')
  final bool isResolved;
  @JsonKey(name: 'resolved_at')
  final DateTime? resolvedAt;

  Alert({
    required this.id,
    required this.userId,
    required this.type,
    required this.message,
    required this.timestamp,
    required this.isResolved,
    this.resolvedAt,
  });

  factory Alert.fromJson(Map<String, dynamic> json) => _$AlertFromJson(json);
  Map<String, dynamic> toJson() => _$AlertToJson(this);

  // UI Helper Methods

  /// Alarm türüne göre renk döndürür
  Color getColor() {
    switch (type) {
      case AppConstants.alertTypeFall:
        return Colors.red.shade700;
      case AppConstants.alertTypeHrHigh:
      case AppConstants.alertTypeHrLow:
        return Colors.orange.shade700;
      case AppConstants.alertTypeButton:
        return Colors.purple.shade700;
      case AppConstants.alertTypeInactivity:
        return Colors.amber.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  /// Alarm türüne göre icon döndürür
  IconData getIcon() {
    switch (type) {
      case AppConstants.alertTypeFall:
        return Icons.person_off;
      case AppConstants.alertTypeHrHigh:
      case AppConstants.alertTypeHrLow:
        return Icons.favorite;
      case AppConstants.alertTypeButton:
        return Icons.warning;
      case AppConstants.alertTypeInactivity:
        return Icons.access_time;
      default:
        return Icons.notifications;
    }
  }

  /// Alarm türüne göre kullanıcı dostu başlık
  String getTypeTitle() {
    switch (type) {
      case AppConstants.alertTypeFall:
        return 'Düşme';
      case AppConstants.alertTypeHrHigh:
        return 'Yüksek Nabız';
      case AppConstants.alertTypeHrLow:
        return 'Düşük Nabız';
      case AppConstants.alertTypeButton:
        return 'Panik Butonu';
      case AppConstants.alertTypeInactivity:
        return 'Hareketsizlik';
      default:
        return 'Alarm';
    }
  }

  Alert copyWith({
    int? id,
    int? userId,
    String? type,
    String? message,
    DateTime? timestamp,
    bool? isResolved,
    DateTime? resolvedAt,
  }) {
    return Alert(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      isResolved: isResolved ?? this.isResolved,
      resolvedAt: resolvedAt ?? this.resolvedAt,
    );
  }
}
