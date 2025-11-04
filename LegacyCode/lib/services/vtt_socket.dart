import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:trpg_frontend/models/marker.dart';

class VttSocket {
  final String base; // 예: http://localhost:4000
  IO.Socket? _socket;

  VttSocket(this.base);

  void connect({
    void Function(marker m)? onmarkerCreated,
    void Function(marker m)? onmarkerMoved,
    void Function(int markerId)? onmarkerDeleted,
  }) {
    // namespace '/vtt'
    _socket = IO.io(
  'http://localhost:11123/chat',
  IO.OptionBuilder()
      .setTransports(['websocket'])
      .enableForceNew()
      .setQuery({
        'marker': marker, // ✅ 이 방식이 모든 플랫폼에서 작동
      })
      .build(),
  );

    _socket!.onConnect((_) {});
    _socket!.on('markerCreated', (data) {
      if (data is Map && data['marker'] is Map) {
        onmarkerCreated?.call(
          marker.fromJson(Map<String, dynamic>.from(data['marker'])),
        );
      }
    });
    _socket!.on('markerMoved', (data) {
      if (data is Map && data['marker'] is Map) {
        onmarkerMoved?.call(
          marker.fromJson(Map<String, dynamic>.from(data['marker'])),
        );
      }
    });
    _socket!.on('markerDeleted', (data) {
      final id = (data is Map) ? data['markerId'] : null;
      if (id is int) onmarkerDeleted?.call(id);
    });
    _socket!.connect();
  }

  void dispose() {
    _socket?.dispose();
    _socket = null;
  }
}
