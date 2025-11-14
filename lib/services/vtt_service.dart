import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'; // [신규] debugPrint를 위해 import
import 'package:trpg_frontend/models/token.dart'; // VTT 토큰 모델
import 'package:trpg_frontend/models/vtt_scene.dart'; // VTT 맵(씬) 모델
import 'package:trpg_frontend/models/map_asset.dart'; // [신규] MapAsset 모델 import
import 'ApiClient.dart'; // Dio 클라이언트

/// VTT (맵, 토큰) 관련 REST API 서비스
/// [참고] VttSocketService와 달리 일회성 데이터 요청/생성/수정/삭제를 담당합니다.
class VttService {
  static VttService? _instance;
  static VttService get instance => _instance ??= VttService._();
  VttService._();

  final ApiClient _apiClient = ApiClient.instance;

  // =======================================================================
  // ✨ VTT 맵 (Scene) API Methods (vttmap.controller.ts 기반)
  // =======================================================================
  static const String _vttMapPath = '/vttmaps';

  /// 방(Room) ID로 모든 맵(씬) 목록 가져오기
  /// [API] GET /vttmaps?roomId=:roomId
  Future<List<VttScene>> getVttMapsByRoom(String roomId) async {
    try {
      final res = await _apiClient.dio.get(
        _vttMapPath,
        queryParameters: {'roomId': roomId},
      );

      final List<dynamic> data = res.data as List<dynamic>;
      // [중요] VttScene.fromJson이 백엔드 VttMapDto와 일치해야 함
      return data
          .map((item) => VttScene.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      debugPrint(
          '[VttService] getVttMapsByRoom Error: ${e.response?.data ?? e.message}');
      throw Exception('맵 목록 로딩 실패: ${e.response?.data['message'] ?? e.message}');
    } catch (e) {
      debugPrint('[VttService] getVttMapsByRoom Error: $e');
      throw Exception('알 수 없는 오류 발생: $e');
    }
  }

  /// 특정 맵(씬) ID로 상세 정보 가져오기
  /// [API] GET /vttmaps/:mapId
  Future<VttScene> getVttMap(String mapId) async {
    try {
      final res = await _apiClient.dio.get('$_vttMapPath/$mapId');

      // [수정됨] 백엔드는 { message, vttMap } 객체를 반환
      if (res.data != null && res.data['vttMap'] != null) {
        return VttScene.fromJson(res.data['vttMap'] as Map<String, dynamic>);
      }
      // VttMapDto를 바로 반환하는 경우 (호환성 유지)
      return VttScene.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      debugPrint(
          '[VttService] getVttMap Error: ${e.response?.data ?? e.message}');
      throw Exception('맵 정보 로딩 실패: ${e.response?.data['message'] ?? e.message}');
    } catch (e) {
      debugPrint('[VttService] getVttMap Error: $e');
      throw Exception('알 수 없는 오류 발생: $e');
    }
  }

  /// 새로운 맵(씬) 생성하기
  /// [API] POST /vttmaps/rooms/:roomId/vttmaps
  // --- [수정됨] ---
  // 'name'만 받는 대신, VttScene.toCreateJson()이 생성한 Map 데이터를 받도록 변경
  // (이 데이터에는 name, width, height 등이 모두 포함되어 있어야 함)
  Future<VttScene> createVttMap(
      String roomId, Map<String, dynamic> createData) async {
    final String path = '$_vttMapPath/rooms/$roomId/vttmaps';

    // [수정됨] body가 파라미터로 받은 createData를 사용하도록 수정
    final Map<String, dynamic> body = createData;
    // --- [수정 끝] ---

    try {
      final res = await _apiClient.dio.post(
        path, // 수정된 경로 사용
        data: body,
      );
      // [수정됨] 백엔드는 생성된 엔티티가 아닌 { message, vttMap } 객체를 반환
      if (res.data != null && res.data['vttMap'] != null) {
        return VttScene.fromJson(res.data['vttMap'] as Map<String, dynamic>);
      } else {
        throw Exception('맵 생성 응답 형식이 올바르지 않습니다.');
      }
    } on DioException catch (e) {
      debugPrint(
          '[VttService] createVttMap Error: ${e.response?.data ?? e.message}');
      throw Exception('맵 생성 실패: ${e.response?.data['message'] ?? e.message}');
    } catch (e) {
      debugPrint('[VttService] createVttMap Error: $e');
      throw Exception('알 수 없는 오류 발생: $e');
    }
  }

  /// 맵(씬) 정보 업데이트 (GM이 맵 설정을 변경할 때)
  /// [API] PATCH /vttmaps/:mapId
  Future<VttScene> updateVttMap(
      String mapId, Map<String, dynamic> updateData) async {
    try {
      final res = await _apiClient.dio.patch(
        '$_vttMapPath/$mapId',
        data: updateData,
      );
      // [수정됨] 백엔드는 { message, vttMap } 객체를 반환
      if (res.data != null && res.data['vttMap'] != null) {
        return VttScene.fromJson(res.data['vttMap'] as Map<String, dynamic>);
      } else {
        throw Exception('맵 업데이트 응답 형식이 올바르지 않습니다.');
      }
    } on DioException catch (e) {
      debugPrint(
          '[VttService] updateVttMap Error: ${e.response?.data ?? e.message}');
      throw Exception('맵 업데이트 실패: ${e.response?.data['message'] ?? e.message}');
    } catch (e) {
      debugPrint('[VttService] updateVttMap Error: $e');
      throw Exception('알 수 없는 오류 발생: $e');
    }
  }

  /// 맵(씬) 삭제하기
  /// [API] DELETE /vttmaps/:mapId
  Future<void> deleteVttMap(String mapId) async {
    final String path = '$_vttMapPath/$mapId';
    try {
      // ApiClient의 dio 인스턴스를 사용하여 delete 요청
      await _apiClient.dio.delete(path);
    } on DioException catch (e) {
      debugPrint(
          '[VttService] deleteMap Error: ${e.response?.data ?? e.message}');
      // 백엔드 vttmap.controller.ts의 deleteVttMap 참조
      throw Exception('맵 삭제 실패: ${e.response?.data['message'] ?? e.message}');
    } catch (e) {
      debugPrint('[VttService] deleteMap Error: $e');
      throw Exception('알 수 없는 오류 발생: $e');
    }
  }

  /// VTT 맵 이미지 업로드용 Presigned URL 받기
  /// [API] POST /vttmaps/rooms/:roomId/vttmaps/presigned-url
  Future<Map<String, dynamic>> getPresignedUrlForVttMapImage({
    required String roomId,
    required String fileName,
    required String contentType,
  }) async {
    try {
      final res = await _apiClient.dio.post(
        '$_vttMapPath/rooms/$roomId/vttmaps/presigned-url', // [수정됨] 접두사 추가
        data: {
          'fileName': fileName,
          'contentType': contentType,
        },
      );
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      debugPrint(
          '[VttService] getPresignedUrl Error: ${e.response?.data ?? e.message}');
      throw Exception(
          'Presigned URL 받기 실패: ${e.response?.data['message'] ?? e.message}');
    } catch (e) {
      debugPrint('[VttService] getPresignedUrl Error: $e');
      throw Exception('알 수 없는 오류 발생: $e');
    }
  }

  // =======================================================================
  // ✨ VTT 토큰 (Token) API Methods (token.controller.ts 기반)
  // =======================================================================
  static const String _tokenPath = '/tokens';

  /// 맵(씬) ID로 모든 토큰 가져오기
  /// [API] GET /tokens?mapId=:mapId
  Future<List<Token>> getTokensByMap(String mapId) async {
    try {
      // --- 🚨 [수정됨] 경로 및 파라미터 방식 변경 ---
      final res = await _apiClient.dio.get(
        _tokenPath, // '/tokens'
        queryParameters: {'mapId': mapId}, // ?mapId=...
      );
      // --- 🚨 [수정 끝] ---

      final List<dynamic> data = res.data as List<dynamic>;
      return data
          .map((item) => Token.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      debugPrint(
          '[VttService] getTokensByMap Error: ${e.response?.data ?? e.message}');
      throw Exception('토큰 목록 로딩 실패: ${e.response?.data['message'] ?? e.message}');
    } catch (e) {
      debugPrint('[VttService] getTokensByMap Error: $e');
      throw Exception('알 수 없는 오류 발생: $e');
    }
  }

  /// 새 토큰 생성하기
  /// [API] POST /tokens
  Future<Token> createToken(
      String mapId, Map<String, dynamic> createData) async {
    try {
      // --- 🚨 [수정됨] API 경로 및 body 수정 ---
      // mapId를 body에 포함
      final body = {
        ...createData,
        'mapId': mapId,
      };

      final res = await _apiClient.dio.post(
        _tokenPath, // '/tokens'
        data: body,
      );
      // --- 🚨 [수정 끝] ---

      // 백엔드 응답은 { message, token } 형태
      if (res.data != null && res.data['token'] != null) {
        return Token.fromJson(res.data['token']);
      } else {
        throw Exception('토큰 생성 응답 형식이 올바르지 않습니다.');
      }
    } on DioException catch (e) {
      debugPrint(
          '[VttService] createToken Error: ${e.response?.data ?? e.message}');
      throw Exception('토큰 생성 실패: ${e.response?.data['message'] ?? e.message}');
    } catch (e) {
      debugPrint('[VttService] createToken Error: $e');
      throw Exception('알 수 없는 오류 발생: $e');
    }
  }

  /// 토큰 정보 업데이트 (이름, 이미지, 시트 연결 등)
  /// [API] PATCH /tokens/:id
  Future<Token> updateToken(String id, Map<String, dynamic> updateData) async {
    try {
      final res = await _apiClient.dio.patch(
        '$_tokenPath/$id',
        data: updateData,
      );

      // 백엔드 응답은 { message, token } 형태
      if (res.data != null && res.data['token'] != null) {
        return Token.fromJson(res.data['token']);
      } else {
        throw Exception('토큰 업데이트 응답 형식이 올바르지 않습니다.');
      }
    } on DioException catch (e) {
      debugPrint(
          '[VttService] updateToken Error: ${e.response?.data ?? e.message}');
      throw Exception(
          '토큰 업데이트 실패: ${e.response?.data['message'] ?? e.message}');
    } catch (e) {
      debugPrint('[VtService] updateToken Error: $e');
      throw Exception('알 수 없는 오류 발생: $e');
    }
  }

  /// 토큰 삭제하기
  /// [API] DELETE /tokens/:id
  Future<void> deleteToken(String id) async {
    try {
      await _apiClient.dio.delete('$_tokenPath/$id');
      return;
    } on DioException catch (e) {
      debugPrint(
          '[VttService] deleteToken Error: ${e.response?.data ?? e.message}');
      throw Exception('맵 삭제 실패: ${e.response?.data['message'] ?? e.message}');
    } catch (e) {
      debugPrint('[VtService] deleteToken Error: $e');
      throw Exception('알 수 없는 오류 발생: $e');
    }
  }

  // =======================================================================
  // 🎨 [신규] VTT 맵 에셋 (MapAsset) API Methods
  // =======================================================================
  static const String _s3Path = '/s3'; // S3 컨트롤러 경로 (가정)
  static const String _mapAssetPath = '/map-asset'; // MapAsset 컨트롤러 경로 (가정)

  /// 캔버스 이미지 업로드용 Presigned URL 받기
  /// [API] POST /s3/presigned-url
  Future<String> getUploadPresignedUrl(String roomId, String extension) async {
    const String path = '$_s3Path/presigned-url';
    try {
      final res = await _apiClient.dio.post(
        path,
        data: {'extension': extension},
        queryParameters: {'roomId': roomId}, // S3 경로 구분을 위해 roomId 전달
      );

      // 백엔드가 { "url": "..." } 형태로 반환한다고 가정
      if (res.data != null && res.data['url'] != null) {
        return res.data['url'] as String;
      } else {
        throw Exception('Presigned URL 응답 형식이 올바르지 않습니다.');
      }
    } on DioException catch (e) {
      debugPrint(
          '[VttService] getUploadPresignedUrl Error: ${e.response?.data ?? e.message}');
      throw Exception(
          '업로드 URL 요청 실패: ${e.response?.data['message'] ?? e.message}');
    } catch (e) {
      debugPrint('[VtService] getUploadPresignedUrl Error: $e');
      throw Exception('알 수 없는 오류 발생: $e');
    }
  }

  /// 새 맵 에셋(이미지) 생성하기 (S3 업로드 완료 후 호출)
  /// [API] POST /map-asset
  Future<MapAsset> createMapAsset(
    String mapId,
    String url,
    double x,
    double y,
    double width,
    double height,
  ) async {
    try {
      final body = {
        'mapId': mapId,
        'url': url,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

      final res = await _apiClient.dio.post(
        _mapAssetPath,
        data: body,
      );

      // 백엔드 응답이 { message, mapAsset } 형태라고 가정 (token.controller.ts 참조)
      if (res.data != null && res.data['mapAsset'] != null) {
        return MapAsset.fromJson(res.data['mapAsset']);
      } else {
        throw Exception('맵 에셋 생성 응답 형식이 올바르지 않습니다.');
      }
    } on DioException catch (e) {
      debugPrint(
          '[VttService] createMapAsset Error: ${e.response?.data ?? e.message}');
      throw Exception(
          '맵 에셋 생성 실패: ${e.response?.data['message'] ?? e.message}');
    } catch (e) {
      debugPrint('[VttService] createMapAsset Error: $e');
      throw Exception('알 수 없는 오류 발생: $e');
    }
  }
}