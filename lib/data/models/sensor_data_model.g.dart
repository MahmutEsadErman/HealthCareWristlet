// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sensor_data_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

HeartRateData _$HeartRateDataFromJson(Map<String, dynamic> json) =>
    HeartRateData(
      value: (json['value'] as num).toDouble(),
      timestamp: json['timestamp'] as String?,
    );

Map<String, dynamic> _$HeartRateDataToJson(HeartRateData instance) =>
    <String, dynamic>{'value': instance.value, 'timestamp': instance.timestamp};

IMUData _$IMUDataFromJson(Map<String, dynamic> json) => IMUData(
  xAxis: (json['x_axis'] as num).toDouble(),
  yAxis: (json['y_axis'] as num).toDouble(),
  zAxis: (json['z_axis'] as num).toDouble(),
  gx: (json['gx'] as num?)?.toDouble(),
  gy: (json['gy'] as num?)?.toDouble(),
  gz: (json['gz'] as num?)?.toDouble(),
  timestamp: json['timestamp'] as String?,
);

Map<String, dynamic> _$IMUDataToJson(IMUData instance) => <String, dynamic>{
  'x_axis': instance.xAxis,
  'y_axis': instance.yAxis,
  'z_axis': instance.zAxis,
  'gx': instance.gx,
  'gy': instance.gy,
  'gz': instance.gz,
  'timestamp': instance.timestamp,
};

ButtonData _$ButtonDataFromJson(Map<String, dynamic> json) => ButtonData(
  panicButtonStatus: json['panic_button_status'] as bool,
  timestamp: json['timestamp'] as String?,
);

Map<String, dynamic> _$ButtonDataToJson(ButtonData instance) =>
    <String, dynamic>{
      'panic_button_status': instance.panicButtonStatus,
      'timestamp': instance.timestamp,
    };
