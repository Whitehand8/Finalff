import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:trpg_frontend/models/token.dart';
import 'package:trpg_frontend/models/vtt_scene.dart';
import 'package:trpg_frontend/models/map_asset.dart'; // [신규] MapAsset 모델
import 'package:trpg_frontend/services/token_manager.dart';
import 'package:flutter/material.dart';

class VttSocketService with ChangeNotifier {
  static const String _socketUrl = 'http://localhost:11123/vtt';

  final String roomId;
  IO.Socket? _socket;

  VttScene? _scene;
  VttScene? get scene => _scene;

  final Map<String, Token> _tokens = {};
  Map<String, Token> get tokens => _tokens;

  // --- [신규] MapAsset 상태 ---
  final Map<String, MapAsset> _mapAssets = {};
  Map<String, MapAsset> get mapAssets => _mapAssets;
  // --- [신규 끝] ---

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  bool _isUploading = false;
  bool get isUploading => _isUploading;

  VoidCallback? _onUploadImageRequest;

  // --- 🚨 [신규] ---
  // 연결 시도 중복을 막기 위한 내부 상태 플래그
  bool _isConnecting = false;
  // --- 🚨 [신규 끝] ---

  final Function(String eventName, dynamic data) onRoomEvent;

  VttSocketService({
    required this.roomId,
    required this.onRoomEvent,
  });

  /// [신규] 방 입장 시 소켓 서버에 연결하고 VTT '룸'에만 참여합니다.
  Future<void> connect() async {
    // 이미 연결 완료되었다면 아무것도 하지 않음
    if (_isConnected) {
      debugPrint('[VttSocket] 이미 연결되어 있습니다.');
      return;
    }

    // --- 🚨 [수정] ---
    // 'connecting' 이나 'status' 대신 내부 플래그(_isConnecting)를 확인합니다.
    if (_isConnecting) {
      debugPrint('[VttSocket] 이미 연결 시도 중입니다.');
      return;
    }
    // --- 🚨 [수정 끝] ---

    // 연결 시도 시작
    _isConnecting = true;

    final token = await TokenManager.instance.getAccessToken();
    if (token == null) {
      debugPrint('[VttSocket] 인증 토큰이 없어 연결할 수 없습니다.');
      _isConnecting = false; // [수정] 연결 시도 종료
      return;
    }

    debugPrint('[VttSocket] VTT 소켓 연결 시도... URL: $_socketUrl');

    _socket = IO.io(
      _socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableForceNew()
          .setAuth({'token': token})
          .build(),
    );

    // --- 소켓 이벤트 리스너 설정 ---

    _socket!.onConnect((_) {
      _isConnected = true;
      _isConnecting = false; // [수정] 연결 성공 시 플래그 리셋
      debugPrint('[VttSocket] VTT 소켓 연결 성공 (ID: ${_socket!.id})');

      _socket!.emit('joinRoom', {'roomId': roomId});

      notifyListeners();
    });

    _socket!.on('joinedRoom', (data) {
      debugPrint('[VtSocket] VTT 룸 참여 완료: $data');
    });

    _socket!.on('joinedMap', (data) {
      debugPrint('[VttSocket] 맵 참여 완료 및 초기 상태 수신');
      _tokens.clear();
      _mapAssets.clear(); // [신규] 맵 에셋 비우기

      if (data['map'] != null) {
        _scene = VttScene.fromJson(data['map']);
      }
      if (data['tokens'] != null) {
        for (var tokenData in (data['tokens'] as List)) {
          final token = Token.fromJson(tokenData as Map<String, dynamic>);
          _tokens[token.id] = token;
        }
      }
      // [신규] 맵 에셋 목록 로드 (백엔드가 'mapAssets' 키로 보내준다고 가정)
      if (data['mapAssets'] != null) {
        for (var assetData in (data['mapAssets'] as List)) {
          final asset = MapAsset.fromJson(assetData as Map<String, dynamic>);
          _mapAssets[asset.id] = asset;
        }
      }
      notifyListeners();
    });

    _socket!.on('mapUpdated', (data) {
      debugPrint('[VttSocket] 맵 업데이트 수신');
      if (data != null && data['id'] == _scene?.id) {
        _scene = VttScene.fromJson(data);
        notifyListeners();
      }
    });

    _socket!.on('mapCreated', (data) {
      debugPrint('[VttSocket] 새 맵 생성됨');
      final newMapId = (data as Map<String, dynamic>)['id'] as String?;
      if (newMapId != null && _scene == null) {
        debugPrint('[VttSocket] 생성된 새 맵 $newMapId 에 자동으로 입장합니다.');
        joinMap(newMapId);
      }
      onRoomEvent('mapCreated', data);
    });

    _socket!.on('mapDeleted', (data) {
      debugPrint('[VttSocket] 맵 삭제됨');
      if (data['id'] == _scene?.id) {
        _scene = null;
        _tokens.clear();
        _mapAssets.clear(); // [신규] 맵 에셋 비우기
        notifyListeners();
      }
      onRoomEvent('mapDeleted', data);
    });

    // --- Token 리스너 ---
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

    // --- [신규] MapAsset 리스너 ---
    _socket!.on('map_asset_created', (data) {
      debugPrint('[VttSocket] 맵 에셋 생성됨');
      final asset = MapAsset.fromJson(data);
      _mapAssets[asset.id] = asset;
      notifyListeners();
    });

    _socket!.on('map_asset_updated', (data) {
      debugPrint('[VttSocket] 맵 에셋 업데이트됨');
      final asset = MapAsset.fromJson(data);
      _mapAssets[asset.id] = asset;
      notifyListeners();
    });

    _socket!.on('map_asset_deleted', (data) {
      debugPrint('[VttSocket] 맵 에셋 삭제됨');
      final id = data['id'] as String?;
      if (id != null) {
        _mapAssets.remove(id);
        notifyListeners();
      }
    });
    // --- [신규 끝] ---


    _socket!.onDisconnect((_) {
      _isConnected = false;
      _isConnecting = false; // [수정] 연결 끊김 시 플래그 리셋
      _scene = null;
      _tokens.clear();
      _mapAssets.clear(); // [신규] 맵 에셋 비우기
      debugPrint('[VttSocket] VTT 소켓 연결 끊김');
      notifyListeners();
    });

    _socket!.onError((data) => debugPrint('[VttSocket] VTT 소켓 오류: $data'));

    _socket!.onConnectError((data) {
      debugPrint('[VttSocket] VTT 소켓 연결 오류: $data');
      _isConnected = false;
      _isConnecting = false; // [수정] 연결 오류 시 플래그 리셋
      notifyListeners();
    });

    _socket!.connect(); // 비동기 연결 시도
  }

  /// [수정됨] 특정 맵(씬)에 참여합니다.
  Future<void> joinMap(String mapId) async {
    if (_socket == null || !_socket!.connected) {
      debugPrint('[VttSocket] 소켓이 연결되지 않아 맵에 참여할 수 없습니다.');
      return;
    }

    if (_scene != null && _scene!.id == mapId) {
      debugPrint('[VttSocket] 이미 맵 $mapId 에 입장해 있습니다.');
      return;
    }

    debugPrint('[VttSocket] 맵 변경/참여 시도: $mapId');

    if (_scene != null) {
      _socket!.emit('leaveMap', {'mapId': _scene!.id});
    }

    // [신규] 맵을 떠날 때 이전 맵의 데이터 즉시 정리
    _scene = null;
    _tokens.clear();
    _mapAssets.clear();
    notifyListeners(); // 맵이 비어있는 상태로 즉시 UI 업데이트

    _socket!.emit('joinMap', {'mapId': mapId});
  }

/// VTTCanvas(또는 다른 위젯)에서 업로드 상태를 변경할 때 호출
  void setIsUploading(bool value) {
    if (_isUploading == value) return; // 같은 상태면 알림 방지
    _isUploading = value;
    notifyListeners();
  }

  /// VTTCanvas가 자신의 업로드 로직(_handleImageUpload)을 서비스에 등록
  void registerUploadImageHandler(VoidCallback handler) {
    _onUploadImageRequest = handler;
  }

  /// RoomScreen의 버튼이 호출할 트리거
  void triggerImageUpload() {
    // 핸들러가 등록되었는지, 현재 업로드 중이 아닌지 확인
    if (_onUploadImageRequest != null && !_isUploading) {
      _onUploadImageRequest?.call();
    }
  }
  // --- 🚨 [추가 끝] ---
  // --- 소켓 이벤트 송신 (Emitter) ---

  void sendMapUpdate(VttScene updatedScene) {
    if (_socket == null || !_socket!.connected) return;

    final Map<String, dynamic> payload = {
      'mapId': updatedScene.id,
      'updates': updatedScene.toUpdateJson(),
    };

    debugPrint('[VttSocket] 맵 업데이트 전송: ${payload['updates']}');
    _socket!.emit('updateMap', payload);
  }

  void moveToken(String tokenId, double x, double y) {
    if (_socket == null || !_socket!.connected) return;

    final Map<String, dynamic> payload = {
      'tokenId': tokenId,
      'x': x,
      'y': y,
    };
    _socket!.emit('moveToken', payload);
  }

  // --- [신규] MapAsset Emitters ---

  /// 맵 에셋의 위치 또는 크기 변경을 서버로 전송합니다.
  void sendUpdateMapAsset(
    String assetId,
    double x,
    double y,
    double width,
    double height,
  ) {
    if (_socket == null || !_socket!.connected) return;

    final Map<String, dynamic> payload = {
      'assetId': assetId,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
    // vtt_canvas.dart에서 정의한 이벤트 이름
    _socket!.emit('update_map_asset', payload);
  }

  /// 맵 에셋 삭제를 서버로 전송합니다.
  void sendDeleteMapAsset(String assetId) {
    if (_socket == null || !_socket!.connected) return;

    final Map<String, dynamic> payload = {
      'assetId': assetId,
    };
     // vtt_canvas.dart에서 정의한 이벤트 이름
    _socket!.emit('delete_map_asset', payload);
  }
  // --- [신규 끝] ---


  @override
  void dispose() {
    debugPrint('[VtSocket] VttSocketService 해제. 소켓 연결 종료.');
    _socket?.dispose();
    super.dispose();
  }
}