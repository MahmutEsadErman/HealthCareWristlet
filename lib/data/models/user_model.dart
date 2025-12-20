import 'package:json_annotation/json_annotation.dart';

part 'user_model.g.dart';

@JsonSerializable()
class User {
  final int id;
  final String username;
  @JsonKey(name: 'user_type')
  final String userType; // 'patient' or 'caregiver'

  User({
    required this.id,
    required this.username,
    required this.userType,
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);

  bool get isPatient => userType == 'patient';
  bool get isCaregiver => userType == 'caregiver';
}

@JsonSerializable()
class LoginResponse {
  @JsonKey(name: 'access_token')
  final String accessToken;
  @JsonKey(name: 'user_type')
  final String userType;
  @JsonKey(name: 'user_id')
  final int userId;

  LoginResponse({
    required this.accessToken,
    required this.userType,
    required this.userId,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) =>
      _$LoginResponseFromJson(json);
  Map<String, dynamic> toJson() => _$LoginResponseToJson(this);
}

@JsonSerializable()
class RegisterRequest {
  final String username;
  final String password;
  @JsonKey(name: 'user_type')
  final String userType;

  RegisterRequest({
    required this.username,
    required this.password,
    required this.userType,
  });

  factory RegisterRequest.fromJson(Map<String, dynamic> json) =>
      _$RegisterRequestFromJson(json);
  Map<String, dynamic> toJson() => _$RegisterRequestToJson(this);
}

@JsonSerializable()
class RegisterResponse {
  final String message;
  @JsonKey(name: 'user_id')
  final int userId;

  RegisterResponse({
    required this.message,
    required this.userId,
  });

  factory RegisterResponse.fromJson(Map<String, dynamic> json) =>
      _$RegisterResponseFromJson(json);
  Map<String, dynamic> toJson() => _$RegisterResponseToJson(this);
}
