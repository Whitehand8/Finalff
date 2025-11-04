import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:trpg_frontend/models/chat.dart'; // 기존 import 경로 유지
import 'auth_service.dart';
import 'Token_manager.dart';

class ChatService with ChangeNotifier {
  final int chatRoomId; 
  IO.Socket? _socket;
  bool _isDisposed = false;

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => _messages;

  // ✅ 1. 연결 상태를 관리할 변수 추가
  bool _isConnected = false;
  // ✅ 2. UI가 연결 상태를 알 수 있도록 getter 추가
  bool get isConnected => _isConnected;

  ChatService(this.chatRoomId) {
    debugPrint('[ChatService] 초기화 (ChatRoom ID: $chatRoomId)');
    _init();
  }

  Future<void> _init() async {
    // 순서 변경: 로그를 먼저 가져오고, 그 동안 UI가 빌드되도록 함
    await _fetchInitialLogs(); 
    // 웹소켓 연결은 백그라운드에서 계속 시도
    _connectWebSocket();
  }

  Future<void> _connectWebSocket() async {
    if (_isDisposed) return;

    // (가독성을 위해) 변수명 소문자로 변경
    final token = await TokenManager.instance.getAccessToken(); 
    if (token == null) {
      debugPrint('[ChatService] WebSocket 연결 실패: 토큰 없음');
      return;
    }

    // 포트 11122 (HTTP)와 11123 (WebSocket)이 다른 것은
    // NestJS 백엔드 구성상 일반적이므로 일단 유지합니다. (서버 설정 확인 필요)
    _socket = IO.io(
      'http://localhost:11123/chat', // 백엔드 ChatGateway 포트 및 네임스페이스
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableForceNew()
          // ✅ [수정] 헤더 방식을 쿼리 파라미터 방식으로 변경
          .setQuery({
            'token': token,
          })
          .build(),
    );

    _socket!
      ..onConnect((_) {
        if (!_isDisposed) {
          debugPrint('[ChatService] WebSocket 연결 성공');
          // ✅ 3. 연결 상태 true로 변경하고 UI에 알림
          _isConnected = true; 
          notifyListeners();
          _joinRoom();
        }
      })
      ..on('joinedRoom', (_) {
        if (!_isDisposed) debugPrint('[ChatService] 방 참여 성공: $chatRoomId');
      })
      ..on('newMessage', (data) {
        // ✅ 4. (치명적 버그 수정) 논리 뒤집기!
        // if (!_isDisposed) return;  <- (X)
        if (_isDisposed) return; //  <- (O)
        
        try {
          final msg = ChatMessage.fromJson(data as Map<String, dynamic>);
          _messages.add(msg);
          notifyListeners();
        } catch (e) {
          debugPrint('[ChatService] newMessage 파싱 실패: $e');
        }
      })
      ..on('error', (data) {
        if (_isDisposed) return;
        final msg = (data as Map<String, dynamic>)['message'] as String?;
        debugPrint('[ChatService] WebSocket 오류: $msg');
      })
      ..onDisconnect((_) {
        if (!_isDisposed) {
          debugPrint('[ChatService] WebSocket 연결 끊김');
          // ✅ 5. 연결 끊김 상태 false로 변경하고 UI에 알림
          _isConnected = false;
          notifyListeners();
        }
      })
      ..onConnectError((err) {
        if (!_isDisposed) {
          debugPrint('[ChatService] WebSocket 연결 오류: $err');
          // ✅ 6. 연결 오류 상태 false로 변경하고 UI에 알림
          _isConnected = false;
          notifyListeners();
        }
      });

    _socket!.connect();
  }

  void _joinRoom() {
    _socket?.emit('joinRoom', {'roomId': chatRoomId});
  }

  Future<void> _fetchInitialLogs() async {
    final uri = Uri.parse('http://localhost:11122/chat/rooms/$chatRoomId/messages');
    try {
      final token = await TokenManager.instance.getAccessToken();
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        if (_isDisposed) return;
        _messages.clear();
        for (final item in data) {
          if (item is Map<String, dynamic>) {
            try {
              _messages.add(ChatMessage.fromJson(item));
            } catch (e) {
              debugPrint('[ChatService] 로그 아이템 파싱 실패: $e');
            }
          }
        }
        notifyListeners();
      } else {
         debugPrint('[ChatService] 채팅 로그 로딩 실패 (Status: ${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      if (!_isDisposed) debugPrint('[ChatService] 채팅 로그 로딩 중 네트워크 오류: $e');
    }
  }

  Future<void> sendMessage(String content) async {
    // ✅ 7. (오류 수정) _socket!.connected 대신 isConnected 플래그 사용
    if (_isDisposed || !_isConnected) { 
      debugPrint('[ChatService] 소켓이 연결되지 않아 메시지를 보낼 수 없습니다.');
      return;
    }

    final senderId = await AuthService.instance.getCurrentUserId();
    if (senderId == null) {
      debugPrint('[ChatService] 사용자 ID를 가져올 수 없습니다. 로그인이 필요합니다.');
      return;
    }

    final now = DateTime.now().toIso8601String();
    
    final payload = {
      'roomId': chatRoomId,
      'messages': [
        {
          'senderId': senderId,
          'content': content,
          'sentAt': now,
        }
      ]
    };
    _socket?.emit('sendMessage', payload);
  }

  @override
  void dispose() {
    debugPrint('[ChatService] 해제 (ChatRoom ID: $chatRoomId)');
    _isDisposed = true;
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    super.dispose();
  }
}