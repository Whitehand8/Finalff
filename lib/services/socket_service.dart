import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'token_manager.dart';

class SocketService {
  // ✅ 1. 싱글톤 인스턴스 생성
  static final SocketService instance = SocketService._internal();

  // ✅ 2. 비공개 생성자
  SocketService._internal();

  IO.Socket? _socket;
  // [수정 1] 백엔드 ChatGateway 포트(11123)와 일치시킵니다.
  final String _serverUrl = 'http://localhost:11123';

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

    // [핵심] 토큰이 'accessToken' 변수에 저장됩니다.
    final accessToken = await TokenManager.instance.getAccessToken();
    if (accessToken == null) {
      throw Exception("인증 토큰이 없습니다. 로그인이 필요합니다.");
    }

    // '$_serverUrl'은 포트 11123을 사용합니다.
    final uri = '$_serverUrl/chat';

    _socket = IO.io(
      uri, // 수정된 uri 변수 사용
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect() // 수동 connect
          // [수정 2] 'token' (정의되지 않음) 대신 'accessToken' 변수를 사용합니다.
          .setQuery({
            'token': accessToken,
          })
          .build(),
    );

    _socket!
      ..onConnect((_) {
        print('채팅 소켓 연결 성공: ${_socket!.id}');
        isConnectedNotifier.value = true;
      })
      ..onDisconnect((_) {
        print('채팅 소켓 연결 끊김');
        isConnectedNotifier.value = false;
      })
      ..onConnectError((data) {
        print('채팅 소켓 연결 오류: $data');
        isConnectedNotifier.value = false;
      })
      ..onError((data) => print('채팅 소켓 오류: $data'));

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
