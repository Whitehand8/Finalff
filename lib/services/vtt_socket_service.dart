import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:trpg_frontend/models/token.dart';
import 'package:trpg_frontend/models/vtt_scene.dart';
import 'package:trpg_frontend/services/token_manager.dart';
// [수정됨] ApiClient import 제거. VTT 소켓은 다른 포트와 URL을 사용합니다.
// import 'package:trpg_frontend/services/api_client.dart'; 

class VttSocketService with ChangeNotifier {
  // [수정됨] VTT Gateway의 정확한 URL과 네임스페이스를 명시
  static const String _socketUrl = 'http://localhost:11123/vtt';

  final String roomId;
  IO.Socket? _socket;

  VttScene? _scene; // 현재 활성화된 맵(씬)
  VttScene? get scene => _scene;

  final Map<String, Token> _tokens = {};
  Map<String, Token> get tokens => _tokens;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // [신규] 맵 삭제 등 룸 전체 이벤트를 처리하기 위한 콜백
  final Function(String eventName, dynamic data) onRoomEvent;

  VttSocketService(String s, {
    required this.roomId,
    required this.onRoomEvent,
  });

  /// 소켓 연결 및 맵(씬) 참여
  Future<void> connectAndJoin(String mapId) async {
    // 맵만 변경하는 경우 (이미 소켓은 연결됨)
    if (_socket != null && _socket!.connected) {
      debugPrint('[VttSocket] 맵 변경: $mapId');
      // 기존 맵에서 나간 후 새 맵에 참여 (선택 사항이지만 권장)
      if (_scene != null) {
        _socket!.emit('leaveMap', {'mapId': _scene!.id});
      }
      _socket!.emit('joinMap', {'mapId': mapId});
      return;
    }

    final token = await TokenManager.instance.getAccessToken();
    if (token == null) {
      debugPrint('[VttSocket] 인증 토큰이 없어 연결할 수 없습니다.');
      return;
    }

    debugPrint('[VttSocket] VTT 소켓 연결 시도... URL: $_socketUrl');

    _socket = IO.io(
      _socketUrl, // [수정됨] ApiClient.baseUrl 대신 명시적 URL 사용
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableForceNew()
          // [수정됨] 인증 방식: Query -> Auth (ws-auth.middleware.ts와 일치)
          .setAuth({'token': token})
          .build(),
    );

    // --- 소켓 이벤트 리스너 설정 ---

    _socket!.onConnect((_) {
      _isConnected = true;
      debugPrint('[VttSocket] VTT 소켓 연결 성공 (ID: ${_socket!.id})');
      
      // [수정됨] 룸과 맵에 순차적으로 참여
      _socket!.emit('joinRoom', {'roomId': roomId});
      _socket!.emit('joinMap', {'mapId': mapId});
      
      notifyListeners();
    });

    _socket!.on('joinedRoom', (data) {
      debugPrint('[VttSocket] VTT 룸 참여 완료: $data');
    });

    _socket!.on('joinedMap', (data) {
      debugPrint('[VttSocket] 맵 참여 완료 및 초기 상태 수신');
      _tokens.clear(); // 맵을 바꿀 때 토큰 초기화

      if (data['map'] != null) {
        _scene = VttScene.fromJson(data['map']);
      }
      if (data['tokens'] != null) {
        for (var tokenData in (data['tokens'] as List)) {
          final token = Token.fromJson(tokenData as Map<String, dynamic>);
          _tokens[token.id] = token;
        }
      }
      notifyListeners();
    });

    _socket!.on('mapUpdated', (data) {
      debugPrint('[VttSocket] 맵 업데이트 수신');
      if (data != null && data['id'] == _scene?.id) {
        // [수정됨] VttScene.fromJson이 data['map']이 아닌 data 자체를 받도록
        _scene = VttScene.fromJson(data); 
        notifyListeners();
      }
    });

    _socket!.on('mapCreated', (data) {
      debugPrint('[VttSocket] 새 맵 생성됨');
      onRoomEvent('mapCreated', data);
    });

    _socket!.on('mapDeleted', (data) {
      debugPrint('[VttSocket] 맵 삭제됨');
      if (data['id'] == _scene?.id) {
        _scene = null;
        _tokens.clear();
        notifyListeners();
      }
      onRoomEvent('mapDeleted', data);
    });

    _socket!.on('token:created', (data) {
      debugPrint('[VttSocket] 토큰 생성됨');
      final token = Token.fromJson(data);
      _tokens[token.id] = token;
      notifyListeners();
    });

    _socket!.on('token:updated', (data) {
      debugPrint('[VttSocket] 토큰 업데이트됨 (이동 또는 데이터 변경)');
      final token = Token.fromJson(data);
      _tokens[token.id] = token;
      notifyListeners();
    });

    _socket!.on('token:deleted', (data) {
      debugPrint('[VttSocket] 토큰 삭제됨');
      final id = data['id'] as String?;
      if (id != null) {
        _tokens.remove(id);
        notifyListeners();
      }
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      debugPrint('[VttSocket] VTT 소켓 연결 끊김');
      notifyListeners();
    });

    _socket!.onError((data) => debugPrint('[VttSocket] VTT 소켓 오류: $data'));

    _socket!.connect();
  }

  // --- 소켓 이벤트 송신 (Emitter) ---

  /// [신규] 맵(씬) 정보 업데이트 (GM 전용)
  void sendMapUpdate(VttScene updatedScene) {
    if (_socket == null || !_socket!.connected) return;

    final Map<String, dynamic> payload = {
      'mapId': updatedScene.id,
      'updates': updatedScene.toUpdateJson(),
    };
    
    debugPrint('[VttSocket] 맵 업데이트 전송: ${payload['updates']}');
    _socket!.emit('updateMap', payload);
  }

  /// [신규] 토큰 이동 (실시간)
  void moveToken(String tokenId, double x, double y) {
    if (_socket == null || !_socket!.connected) return;

    final Map<String, dynamic> payload = {
      'tokenId': tokenId,
      'x': x,
      'y': y,
    };
    _socket!.emit('moveToken', payload);
  }

  @override
  void dispose() {
    debugPrint('[VttSocket] VttSocketService 해제. 소켓 연결 종료.');
    _socket?.dispose();
    super.dispose();
  }
}
