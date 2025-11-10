import 'dart:async';
import 'package:dio/dio.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'token_manager.dart';

// 외부에서 로그아웃 시 라우팅 처리 가능하도록 콜백 주입
typedef OnUnauthenticatedCallback = void Function();

class ApiClient {
  static ApiClient? _instance;
  static ApiClient get instance => _instance ??= ApiClient._();

  late final Dio _dio;
  final TokenManager _TokenManager = TokenManager.instance;
  Completer<String?>? _refreshCompleter;
  OnUnauthenticatedCallback? _onUnauthenticated;

  ApiClient._() {
    final options = BaseOptions(
      baseUrl: 'http://localhost:11122',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    );
    _dio = Dio(options);
    _dio.interceptors.add(_AuthQueuedInterceptor(this));
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestHeader: true,
        requestBody: true,
        responseBody: true,
        error: true,
        logPrint: (msg) => debugPrint(msg.toString()),
      ));
    }
  }

  void setOnUnauthenticated(OnUnauthenticatedCallback callback) {
    _onUnauthenticated = callback;
  }

  Dio get dio => _dio;

  Future<Map<String, String>> getPresignedUrl(String fileName, String fileType) async {
    try {
      // 🚨 중요: 이 요청은 ApiClient의 인증 인터셉터(_AuthQueuedInterceptor)를
      // 통과해야 하므로, _dio 인스턴스를 사용하는 것이 맞습니다.
      final response = await _dio.post(
        '/s3/presigned-url',
        data: {
          'fileName': fileName,
          'fileType': fileType,
        },
      );

      if (response.statusCode == 201 && response.data != null) {
        // 백엔드가 'presignedUrl'과 'fileUrl'을 반환한다고 가정
        return {
          'presignedUrl': response.data['presignedUrl'] as String,
          'fileUrl': response.data['fileUrl'] as String,
        };
      } else {
        throw Exception('Presigned URL 생성 실패');
      }
    } on DioException catch (e) {
      // 401 오류 등은 인터셉터가 처리하겠지만, 그 외의 오류를 대비
      throw Exception('Presigned URL 요청 오류: ${e.response?.data ?? e.message}');
    }
  }

  /// [신규] 2. S3로 실제 파일 업로드 함수
  /// Dio를 사용해 Presigned URL에 PUT 요청으로 파일을 전송합니다.
  Future<void> uploadFileToS3(String presignedUrl, Uint8List fileBytes, String fileType) async {
    try {
      // 🚨 중요: S3 업로드는 인증 헤더나 기본 BaseUrl이 필요 없습니다.
      // 따라서 ApiClient의 _dio가 아닌, 새 Dio 인스턴스를 사용해야 합니다.
      final s3Dio = Dio(); 
      
      await s3Dio.put(
        presignedUrl,
        data: Stream.fromIterable(fileBytes.map((e) => [e])), // 바이트 데이터를 스트림으로
        options: Options(
          headers: {
            Headers.contentLengthHeader: fileBytes.lengthInBytes,
            Headers.contentTypeHeader: fileType, // 파일의 MIME 타입
          },
        ),
      );
    } on DioException catch (e) {
      throw Exception('S3 업로드 실패: ${e.response?.data ?? e.message}');
    }
  }

  Future<String?> _refreshAccessToken() async {
    // 이미 진행 중이면 기다림
    if (_refreshCompleter != null) {
      return await _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<String?>();
    try {
      final refreshToken = await _TokenManager.getRefreshToken();
      if (refreshToken == null) {
        _refreshCompleter!.complete(null);
        return null;
      }

      final res = await _dio
          .post('/auth/refresh', data: {'refresh_Token': refreshToken});
      final newAccessToken = res.data['access_Token'] as String?;
      final newRefreshToken = res.data['refresh_Token'] as String?;

      if (newAccessToken == null || newRefreshToken == null) {
        throw Exception('Invalid refresh response');
      }

      await _TokenManager.saveTokens(newAccessToken, newRefreshToken);
      _refreshCompleter!.complete(newAccessToken);
      return newAccessToken;
    } catch (e) {
      if (kDebugMode) debugPrint('Token refresh failed: $e');
      await _TokenManager.clearTokens();
      _refreshCompleter!.complete(null);
      rethrow;
    } finally {
      _refreshCompleter = null;
    }
  }
}

class _AuthQueuedInterceptor extends QueuedInterceptor {
  final ApiClient _client;

  _AuthQueuedInterceptor(this._client);

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final Token = await _client._TokenManager.getAccessToken();
    if (Token != null) {
      options.headers['Authorization'] = 'Bearer $Token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      final newToken = await _client._refreshAccessToken();
      if (newToken != null) {
        err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
        try {
          final retry = await _client.dio.fetch(err.requestOptions);
          return handler.resolve(retry);
        } catch (e) {
          // retry 실패 시 원래 에러 반환
          return handler.reject(err);
        }
      } else {
        await _client._TokenManager.clearTokens();
        _client._onUnauthenticated?.call();
        return handler.reject(err);
      }
    }
    handler.next(err);
  }
}
