import 'package:dio/dio.dart'; // 1. DioException을 사용하기 위해 import
import 'package:flutter/foundation.dart';
import 'package:trpg_frontend/models/token.dart';
import 'package:trpg_frontend/services/ApiClient.dart';

/// 토큰(캐릭터, 이미지 소품 등)의 생성, 수정, 삭제를 위한
/// REST API 호출을 담당하는 서비스입니다.
class TokenService {
  TokenService._(); // Private constructor
  static final TokenService instance = TokenService._(); // Singleton instance

  final ApiClient _apiClient = ApiClient.instance;
  static const String _tokenPath = '/tokens';

  /// 새 토큰(사진 또는 캐릭터 토큰)을 맵에 생성합니다.
  Future<Token> createToken({
    required String mapId,
    required String name,
    String? imageUrl,
    double x = 100.0,
    double y = 100.0,
    // [수정됨] 400 오류 방지를 위해 width, height, isVisible는 요청 시 보내지 않음
    // double width = 100.0, 
    // double height = 100.0,
    int? characterSheetId,
    int? npcId,
  }) async {
    try {
      final Map<String, dynamic> body = {
        // 'mapId': mapId, // URL로 전달
        'name': name,
        'imageUrl': imageUrl,
        'x': x,
        'y': y,
        // [수정됨] 400 오류 유발 필드 제거
        // 'width': width,
        // 'height': height,
        // 'isVisible': true,
        'characterSheetId': characterSheetId,
        'npcId': npcId,
      };
      
      body.removeWhere((key, value) => value == null);
      debugPrint('[TokenService] Creating token: $body');

      final response = await _apiClient.dio.post(
        '$_tokenPath/maps/$mapId', // 404 수정 완료된 경로
        data: body,
      );

      // [수정] 백엔드가 { "token": ... }이 아닌 { ... } (토큰 객체)를 직접 반환
      // response.data['token'] 대신 response.data를 직접 파싱
      if (response.data != null) {
        return Token.fromJson(response.data);
      } else {
        throw TokenServiceException('토큰 생성 응답 형식이 올바르지 않습니다. (null body)');
      }
    } on DioException catch (e) { 
      debugPrint('[TokenService] createToken Error: ${e.response?.data ?? e.message}');
      throw TokenServiceException('토큰 생성 실패: ${e.response?.data['message'] ?? e.message}');
    } catch (e) {
      debugPrint('[TokenService] createToken Error: $e');
      // [수정] 오류가 여기서 발생했다면 Json 파싱 오류일 가능성이 높음
      throw TokenServiceException('알 수 없는 오류 발생 (아마도 Json 파싱 실패): $e');
    }
  }

  /// 기존 토큰의 정보를 업데이트합니다. (위치, 크기 등)
  Future<Token> updateToken(
    String tokenId, {
    double? x,
    double? y,
    double? width,
    double? height,
    bool? isVisible,
    String? name,
  }) async {
    try {
      final Map<String, dynamic> body = {};

      if (x != null) body['x'] = x;
      if (y != null) body['y'] = y;
      if (width != null) body['width'] = width;
      if (height != null) body['height'] = height;
      if (isVisible != null) body['isVisible'] = isVisible;
      if (name != null) body['name'] = name;

      if (body.isEmpty) {
        throw TokenServiceException('업데이트할 내용이 없습니다.');
      }

      debugPrint('[TokenService] Updating token $tokenId: $body');

      final response = await _apiClient.dio.patch(
        '$_tokenPath/$tokenId',
        data: body,
      );

      // [수정] createToken과 마찬가지로, 응답 본문(data)을 직접 파싱
      if (response.data != null) {
        return Token.fromJson(response.data);
      } else {
        throw TokenServiceException('토큰 업데이트 응답 형식이 올바르지 않습니다.');
      }
    } on DioException catch (e) { 
      debugPrint('[TokenService] updateToken Error: ${e.response?.data ?? e.message}');
      throw TokenServiceException('토큰 업데이트 실패: ${e.response?.data['message'] ?? e.message}');
    } catch (e) {
      debugPrint('[TokenService] updateToken Error: $e');
      throw TokenServiceException('알 수 없는 오류 발생 (아마도 Json 파싱 실패): $e');
    }
  }

  /// 토큰을 삭제합니다.
  Future<void> deleteToken(String tokenId) async {
    try {
      debugPrint('[TokenService] Deleting token $tokenId');
      await _apiClient.dio.delete('$_tokenPath/$tokenId');
    } on DioException catch (e) { 
      debugPrint('[TokenService] deleteToken Error: ${e.response?.data ?? e.message}');
      throw TokenServiceException('토큰 삭제 실패: ${e.response?.data['message'] ?? e.message}');
    } catch (e) {
      debugPrint('[TokenService] deleteToken Error: $e');
      throw TokenServiceException('알 수 없는 오류 발생: $e');
    }
  }
}

/// TokenService에서 발생하는 특정 예외
class TokenServiceException implements Exception {
  final String message;
  TokenServiceException(this.message);

  @override
  String toString() => 'TokenServiceException: $message';
}