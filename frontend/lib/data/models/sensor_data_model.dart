import 'package:json_annotation/json_annotation.dart';

part 'sensor_data_model.g.dart';

/// Kalp hızı verisi
@JsonSerializable()
class HeartRateData {
  final double value;
  final String? timestamp; // Opsiyonel - ISO 8601 formatı

  HeartRateData({
    required this.value,
    this.timestamp,
  });

  factory HeartRateData.fromJson(Map<String, dynamic> json) =>
      _$HeartRateDataFromJson(json);
  Map<String, dynamic> toJson() => _$HeartRateDataToJson(this);
}

/// IMU (İvmeölçer + Jiroskop) verisi
@JsonSerializable()
class IMUData {
  @JsonKey(name: 'x_axis')
  final double xAxis;
  @JsonKey(name: 'y_axis')
  final double yAxis;
  @JsonKey(name: 'z_axis')
  final double zAxis;
  final double? gx; // Gyroscope X
  final double? gy; // Gyroscope Y
  final double? gz; // Gyroscope Z
  final String? timestamp; // Opsiyonel - ISO 8601 formatı

  IMUData({
    required this.xAxis,
    required this.yAxis,
    required this.zAxis,
    this.gx,
    this.gy,
    this.gz,
    this.timestamp,
  });

  factory IMUData.fromJson(Map<String, dynamic> json) =>
      _$IMUDataFromJson(json);
  Map<String, dynamic> toJson() => _$IMUDataToJson(this);
}

/// Panik butonu verisi
@JsonSerializable()
class ButtonData {
  @JsonKey(name: 'panic_button_status')
  final bool panicButtonStatus;
  final String? timestamp; // Opsiyonel - ISO 8601 formatı

  ButtonData({
    required this.panicButtonStatus,
    this.timestamp,
  });

  factory ButtonData.fromJson(Map<String, dynamic> json) =>
      _$ButtonDataFromJson(json);
  Map<String, dynamic> toJson() => _$ButtonDataToJson(this);
}
