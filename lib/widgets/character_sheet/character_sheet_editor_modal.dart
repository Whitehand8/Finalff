import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trpg_frontend/models/character.dart';
import 'package:trpg_frontend/providers/room_data_provider.dart';
import 'package:trpg_frontend/features/character_sheet/character_sheet_router.dart'; // 이미 존재하는 라우터

enum SheetEditorMode { create, update }

class CharacterSheetEditorModal extends StatefulWidget {
  final SheetEditorMode mode;
  final String systemId; // 'coc7e', 'dnd5e' 등 룰북 ID
  final int participantId; // 시트의 소유자(또는 될) participantId
  final Character? character; // 수정 모드일 때만 전달

  const CharacterSheetEditorModal({
    super.key,
    required this.mode,
    required this.systemId,
    required this.participantId,
    this.character,
  }) : assert(
            mode == SheetEditorMode.create ||
                (mode == SheetEditorMode.update && character != null),
            '수정 모드일 때는 character 객체가 반드시 필요합니다.');

  @override
  State<CharacterSheetEditorModal> createState() =>
      _CharacterSheetEditorModalState();
}

class _CharacterSheetEditorModalState extends State<CharacterSheetEditorModal> {
  // ---------------------------------------------------
  // ⚠️ 참고:
  // 모든 시스템(coc7e, dnd5e)에서 사용하는 모든 키를 정의합니다.
  // 이 방식은 향후 시스템이 많아지면 분리가 필요하지만,
  // 현재 구조에서는 가장 간단하게 'CharacterSheetRouter'로 전달할 수 있습니다.
  // ---------------------------------------------------

  // CoC 7판 키
  static const List<String> _cocGeneralKeys = [
    'name', 'sex', 'age', 'job', 'temporaryInsanity', 'indefiniteInsanity',
    'insanityOutburst'
  ];
  static const List<String> _cocStatKeys = [
    'hp', 'mp', // HP, MP도 data 맵에 저장
    '근력', '건강', '크기', '민첩', '외모', '지능', '교육', '정신력', '행운',
    '회계', '인류학', '감정', '고고학', '매혹', '오르기', '재력', '크툴루신화', '변장', '회피',
    '자동차운전', '전기수리', '말재주', '근접전(격투)', '사격(권총)', '사격(라/산)', '응급처치',
    '역사', '관찰력', '은밀행동', '수영', '투척', '추적', '외국어()', '과학()', '예술/공예()',
    '사격()', '자연', '항법', '오컬트', '중장비 조작', '심리학', '정신분석', '승마', '손놀림',
    '듣기', '자료조사', '열쇠공', '의료', '기계수리', '모국어', '법률', '생존술()'
  ];

  // D&D 5e 키
  static const List<String> _dndGeneralKeys = [
    'name', 'level', 'class', 'race', 'baseAC', 'shield', 'perceptionProficient',
    'hp', 'mp' // D&D도 HP/MP를 data에 저장
  ];
  static const List<String> _dndStatKeys = [
    'STR', 'DEX', 'CON', 'INT', 'WIS', 'CHA'
  ];

  // 모든 키를 통합한 컨트롤러 맵
  final Map<String, TextEditingController> _statControllers = {};
  final Map<String, TextEditingController> _generalControllers = {};

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    // 1. 모든 시스템의 컨트롤러를 초기화합니다.
    final allStatKeys = {..._cocStatKeys, ..._dndStatKeys};
    final allGeneralKeys = {..._cocGeneralKeys, ..._dndGeneralKeys};

    for (final key in allStatKeys) {
      _statControllers[key] = TextEditingController();
    }
    for (final key in allGeneralKeys) {
      _generalControllers[key] = TextEditingController();
    }

    // 2. 수정 모드인 경우, 컨트롤러에 기존 데이터를 채웁니다.
    if (widget.mode == SheetEditorMode.update) {
      _populateControllers(widget.character!.data);
    }
  }

  /// 컨트롤러 맵에 [data]의 값을 채워넣습니다.
  void _populateControllers(Map<String, dynamic> data) {
    data.forEach((key, value) {
      // data 맵의 값이 null이 아니고, 텍스트로 변환 가능한 값일 때
      final textValue = (value != null) ? value.toString() : '';

      if (_statControllers.containsKey(key)) {
        _statControllers[key]!.text = textValue;
      } else if (_generalControllers.containsKey(key)) {
        _generalControllers[key]!.text = textValue;
      }
    });
  }

  @override
  void dispose() {
    // 3. 모든 컨트롤러를 dispose하여 메모리 누수를 방지합니다.
    for (final c in _statControllers.values) {
      c.dispose();
    }
    for (final c in _generalControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// 모든 컨트롤러의 현재 값을 수집하여 [data] 맵으로 반환합니다.
  Map<String, dynamic> _collectData() {
    final Map<String, dynamic> data = {};

    // 헬퍼 함수: 문자열을 int, bool 또는 String으로 파싱
    dynamic parseValue(String text) {
      if (text.isEmpty) return null; // 빈 문자열은 null로 저장
      if (int.tryParse(text) != null) return int.parse(text);
      if (text.toLowerCase() == 'true') return true;
      if (text.toLowerCase() == 'false') return false;
      return text;
    }

    _statControllers.forEach((key, controller) {
      data[key] = parseValue(controller.text);
    });
    _generalControllers.forEach((key, controller) {
      data[key] = parseValue(controller.text);
    });

    return data;
  }

  /// 저장 버튼을 눌렀을 때 실행될 콜백
  Future<void> _onSave() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final data = _collectData();
    final provider = context.read<RoomDataProvider>();
    final navigator = Navigator.of(context); // 비동기 작업 전 context 저장

    try {
      if (widget.mode == SheetEditorMode.create) {
        // 생성
        await provider.createSheet(
          participantId: widget.participantId,
          data: data,
        );
      } else {
        // 수정
        await provider.updateSheet(
          participantId: widget.participantId,
          data: data,
          // TODO: isPublic은 GM만 수정 가능하도록 별도 UI 필요
          // isPublic: ...
        );
      }
      navigator.pop(); // 저장 성공 시 모달 닫기
    } catch (e) {
      // 에러 발생 시
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('저장 실패: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 닫기 버튼을 눌렀을 때 실행될 콜백
  void _onClose() {
    Navigator.of(context).pop();
  }

  /// 텍스트 컨트롤러의 값을 안전하게 int로 파싱 (HP, MP 전달용)
  int _parseInt(TextEditingController? controller) {
    if (controller == null) return 0;
    return int.tryParse(controller.text) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    // CharacterSheetRouter에 전달할 HP, MP 값을 파싱합니다.
    final int hp = _parseInt(_statControllers['hp']);
    final int mp = _parseInt(_statControllers['mp']);

    return Padding(
      // 시트가 화면의 90%를 차지하도록 설정 (DraggableScrollableSheet와 유사)
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 40),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.mode == SheetEditorMode.create
              ? '캐릭터 시트 생성'
              : '캐릭터 시트 수정'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _onClose,
          ),
          actions: [
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: CircularProgressIndicator(),
              )
            else
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: _onSave,
              ),
          ],
        ),
        body: CharacterSheetRouter(
          systemId: widget.systemId,
          statControllers: _statControllers,
          generalControllers: _generalControllers,
          hp: hp,
          mp: mp,
          onSave: _onSave,
          onClose: _onClose,
        ),
      ),
    );
  }
}