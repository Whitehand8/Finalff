// lib/widgets/dice/dice_roll_modal.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trpg_frontend/services/chat_service.dart';
import 'package:trpg_frontend/systems/core/dice.dart'; // ✅ 실제 dice.dart 파일 임포트

class DiceRollModal extends StatefulWidget {
  /// 주사위를 굴리는 사람의 닉네임 (채팅 메시지에 표시됨)
  final String rollerNickname;

  const DiceRollModal({
    super.key,
    required this.rollerNickname,
  });

  @override
  State<DiceRollModal> createState() => _DiceRollModalState();
}

class _DiceRollModalState extends State<DiceRollModal> {
  final _textController = TextEditingController(text: '1d100'); // 기본값
  final _formKey = GlobalKey<FormState>();
  String? _errorText;
  bool _isLoading = false;

  /// "굴리기" 버튼을 눌렀을 때 실행되는 함수
  Future<void> _submitRoll() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    final text = _textController.text.trim();
    Roll result; // ✅ DiceResult가 아닌 Roll 객체 사용

    try {
      // 1. ✅ Dice.roll(text) static 메서드 호출
      result = Dice.roll(text);

      // 2. ✅ Roll 객체의 detail과 total을 사용하여 상세 포맷 생성
      // dice.dart의 Roll 클래스는 detail에 "[3, 5]+4" 와 같은 문자열을 제공합니다.
      // 
      // 요청하신 포맷: "1d4+1d8 = 3 + 5 = 8"
      // 현재 `dice.dart`가 제공하는 포맷: "2d6+4 🎲 [3, 5]+4 = 12"
      //
      // 여기서는 `dice.dart`가 제공하는 'detail'을 그대로 활용하겠습니다.
      final expressionString = "$text 🎲 ${result.detail} = ${result.total}";

      // 3. 채팅 서비스로 전송할 최종 메시지를 만듭니다.
      final chatMessage =
          "[${widget.rollerNickname}] 님이 $expressionString";

      // 4. ChatService를 통해 메시지를 전송합니다.
      if (mounted) {
        context.read<ChatService>().sendMessage(chatMessage);
        Navigator.of(context).pop(); // 성공 시 모달 닫기
      }
    } catch (e) {
      // Dice.roll()에서 오류 발생 시 (예: "1d+5" 또는 지원하지 않는 "1d4+1d8")
      if (mounted) {
        setState(() {
          // dice.dart의 ArgumentError 메시지를 사용
          _errorText = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('주사위 굴리기'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _textController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '주사위 식 (예: 2d6+4, 1d100)',
            errorText: _errorText,
          ),
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submitRoll(),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return '주사위 식을 입력하세요.';
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submitRoll,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('굴리기'),
        ),
      ],
    );
  }
}