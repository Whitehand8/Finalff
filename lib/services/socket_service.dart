import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'token_manager.dart';

class SocketService {
  // ✅ 1. 싱글톤 인스턴스 생성
  static final SocketService instance = SocketService._internal();

  // ✅ 2. 비공개 생성자
  SocketService._internal(); 

  IO.Socket? _socket;
  final String _serverUrl = 'http://localhost:11122';

  // ✅ 3. static 제거
  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier(false);

  IO.Socket get socket {
    if (_socket == null || !_socket!.connected) {
      throw Exception("소켓이 연결되지 않았습니다. connect()를 먼저 호출하세요.");
    }
    return _socket!;
  }

  bool get isConnected => isConnectedNotifier.value;

  // ✅ 4. static 제거
  Future<void> connect() async {
    if (isConnected) return;

    final accessToken = await TokenManager.instance.getAccessToken();
    if (accessToken == null) {
      throw Exception("인증 토큰이 없습니다. 로그인이 필요합니다.");
    }

    final uri = '$_serverUrl/chat';

    _socket = IO.io(
      uri,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setExtraHeaders({'Authorization': 'Bearer $accessToken'})
          .build(),
    );

    _socket!
      ..onConnect((_) {
        print('소켓 연결 성공: ${_socket!.id}');
        isConnectedNotifier.value = true;
      })
      ..onDisconnect((_) {
        print('소켓 연결 끊김');
        isConnectedNotifier.value = false;
      })
      // ... (이하 동일)
      ..onConnectError((data) {
        print('소켓 연결 오류: $data');
        isConnectedNotifier.value = false;
      })
      ..onError((data) => print('소켓 오류: $data'));

    _socket!.connect();
  }

  // ✅ 5. static 제거
  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    isConnectedNotifier.value = false;
  }
}