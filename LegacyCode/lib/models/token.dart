// lib/models/token.dart

import 'package:trpg_frontend/models/user.dart'; // 로그인 응답에 포함된 User 모델

/// 백엔드의 /auth/login 엔드포인트 응답을 모델링하는 클래스입니다.
/// 인증(Authentication) 토큰을 관리합니다.
class AuthTokenResponse {
  final String accessToken;
  final String refreshToken;
  final User user; // 로그인한 사용자의 상세 정보

  AuthTokenResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  /// 백엔드에서 받은 JSON 맵을 AuthTokenResponse 객체로 변환합니다.
  factory AuthTokenResponse.fromJson(Map<String, dynamic> json) {
    // 'access_token' 또는 'refresh_token'이 없는 경우 예외 발생
    if (json['access_token'] == null || json['refresh_token'] == null) {
      throw FormatException(
          "Invalid login response: 'access_token' or 'refresh_token' is missing.");
    }

    // 'user' 객체가 없는 경우 예외 발생
    final userJson = json['user'] as Map<String, dynamic>?;
    if (userJson == null) {
      throw FormatException(
          "Invalid login response: 'user' object is missing.");
    }

    return AuthTokenResponse(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      // 기존 User.fromJson을 사용하여 중첩된 사용자 객체 파싱
      user: User.fromJson(userJson),
    );
  }
}