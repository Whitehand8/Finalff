import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trpg_frontend/services/token_service.dart';
import 'package:trpg_frontend/services/vtt_socket_service.dart';

/// 캔버스에 새 이미지 토큰을 생성하기 위한 모달 위젯입니다.
class CreateTokenModal extends StatefulWidget {
  const CreateTokenModal({super.key});

  @override
  State<CreateTokenModal> createState() => _CreateTokenModalState();
}

class _CreateTokenModalState extends State<CreateTokenModal> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = false;

  /// "확인" 버튼을 눌렀을 때 토큰 생성을 요청하는 함수
  Future<void> _handleCreateToken() async {
    if (!mounted) return;

    final vttSocket = context.read<VttSocketService>();
    final tokenService = TokenService.instance; // Singleton 인스턴스 사용

    // 현재 입장한 맵(씬)의 ID를 가져옵니다.
    final String? mapId = vttSocket.scene?.id;

    if (mapId == null) {
      _showError('현재 입장한 맵이 없습니다. 맵에 먼저 입장해주세요.');
      return;
    }

    final String imageUrl = _urlController.text.trim();
    final String name = _nameController.text.trim();

    if (imageUrl.isEmpty) {
      _showError('이미지 URL을 입력해주세요.');
      return;
    }
    if (name.isEmpty) {
      _showError('토큰 이름을 입력해주세요.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // TokenService를 사용하여 새 토큰 생성을 요청합니다.
      // (x, y 기본값은 서비스에서 100, 100으로 설정됨)
      await tokenService.createToken(
        mapId: mapId,
        name: name,
        imageUrl: imageUrl,
      );

      if (!mounted) return;
      // 생성 성공 시 모달을 닫습니다.
      // (백엔드가 'token:created' 이벤트를 브로드캐스트하여
      // VttSocketService가 자동으로 캔버스를 갱신할 것입니다.)
      Navigator.of(context).pop();
    } on TokenServiceException catch (e) {
      _showError('토큰 생성 실패: ${e.message}');
    } catch (e) {
      _showError('알 수 없는 오류가 발생했습니다: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('새 이미지 토큰 생성'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '토큰 이름',
              hintText: '예: 나무, 보물상자',
            ),
            enabled: !_isLoading,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: '이미지 URL',
              hintText: 'https://example.com/image.png',
            ),
            keyboardType: TextInputType.url,
            enabled: !_isLoading,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _handleCreateToken,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('생성'),
        ),
      ],
    );
  }
}