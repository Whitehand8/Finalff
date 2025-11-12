import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trpg_frontend/providers/room_data_provider.dart';
import 'package:trpg_frontend/models/participant.dart';
import 'package:trpg_frontend/models/character.dart';
import 'package:trpg_frontend/widgets/character/character_list_item.dart';
import 'package:trpg_frontend/widgets/character_sheet/character_sheet_editor_modal.dart';

class ParticipantCharacterPanel extends StatelessWidget {
  const ParticipantCharacterPanel({super.key});

  @override
  Widget build(BuildContext context) {
    // RoomDataProvider의 상태를 구독합니다.
    return Consumer<RoomDataProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.participants.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.error != null) {
          return Center(
            child: Text(
              '오류가 발생했습니다: ${provider.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        // ✅ [수정] Column을 SingleChildScrollView로 변경하여 스크롤
        return SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- 1. 참여자 섹션 ---
                _buildParticipantSection(context, provider),

                const SizedBox(height: 24), // 섹션 간 간격

                // --- 2. 캐릭터 시트 섹션 ---
                _buildCharacterSheetSection(context, provider),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '$count명',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  // === 🟢 [신규] 1. 참여자 섹션 빌드 ===
  Widget _buildParticipantSection(
      BuildContext context, RoomDataProvider provider) {
    final participants = provider.participants;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, '참여자', provider.participants.length),
        ListView.builder(
          itemCount: participants.length,
          shrinkWrap: true, // ✅ SingleChildScrollView 내부에서 크기 자동 조절
          physics:
              const NeverScrollableScrollPhysics(), // ✅ 부모 스크롤과 충돌 방지
          itemBuilder: (context, index) {
            final p = participants[index];
            // ✅ 캐릭터 시트와 상관없이 참여자 정보만 표시
            return _buildSimpleParticipantTile(context, provider, p);
          },
        ),
      ],
    );
  }

  // === 🟢 [신규] 참여자 정보만 간단히 표시하는 타일 ===
  Widget _buildSimpleParticipantTile(
    BuildContext context,
    RoomDataProvider provider,
    Participant p,
  ) {
    final bool isMe = provider.myParticipant?.id == p.id;
    final bool isGM = p.role == 'GM';

    return ListTile(
      leading: Icon(
        isGM ? Icons.shield_outlined : Icons.person_outline,
        color: isGM ? Colors.amber[800] : null,
      ),
      title: Text(
        '${p.nickname}${isMe ? ' (나)' : ''}',
        style: TextStyle(
          fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(isGM ? 'GM' : 'Player'),
      dense: true,
    );
  }

  // === 🟢 [신규] 2. 캐릭터 시트 섹션 빌드 ===
  Widget _buildCharacterSheetSection(
      BuildContext context, RoomDataProvider provider) {
    final characters = provider.characters;
    final bool isGM = provider.isGM;
    final int? myId = provider.myParticipant?.id;

    // 내가 시트를 이미 만들었는지 확인
    final bool iHaveSheet = characters.any((c) => c.participantId == myId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, '캐릭터 시트', characters.length),
        
        // 캐릭터 시트 목록
        ListView.builder(
          itemCount: characters.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (context, index) {
            final character = characters[index];
            final bool isMe = character.participantId == myId;

            // GM이거나, 내 시트이거나, 공개된 시트일 때만 조회/수정 가능
            final bool canView = isGM || isMe || character.isPublic;

            return CharacterListItem(
              character: character,
              onTap: canView
                  ? () {
                      // ✅ [기존 로직 재사용] 수정 모드로 모달 열기
                      _showEditorModal(
                        context: context,
                        mode: 'update',
                        systemId: provider.roomSystemId,
                        character: character,
                      );
                    }
                  : () {}, // 탭 불가능
            );
          },
        ),

        const SizedBox(height: 16),

        // ✅ '내 시트 추가' 버튼 (시트가 없을 때만 표시)
        if (myId != null && !iHaveSheet)
          _buildMyCharacterCreateButton(context, provider),
      ],
    );
  }

  /// '내 캐릭터 시트 추가' 버튼 (기존 코드와 동일)
  Widget _buildMyCharacterCreateButton(
    BuildContext context,
    RoomDataProvider provider,
  ) {
    if (provider.myParticipant == null) {
      return const SizedBox.shrink();
    }

    return Center(
      child: ElevatedButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('내 캐릭터 시트 추가'),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
        ),
        onPressed: () {
          // 'create' 모드로 모달 열기
          _showEditorModal(
            context: context,
            mode: 'create',
            systemId: provider.roomSystemId, // 방의 룰 ID
            myParticipantId: provider.myParticipant!.id, // 내 참여자 ID
          );
        },
      ),
    );
  }

  /// 생성/수정 모달을 띄우는 함수 (이전 수정사항이 적용된 상태)
  void _showEditorModal({
    required BuildContext context,
    required String mode, // 'create' 또는 'update' 문자열
    required String systemId,
    Character? character, // 수정 모드일 때만 전달
    int? myParticipantId, // 생성 모드일 때만 전달
  }) {
    final SheetEditorMode editorMode =
        (mode == 'create') ? SheetEditorMode.create : SheetEditorMode.update;

    // participantId 결정:
    final int participantId;
    if (editorMode == SheetEditorMode.create) {
      assert(myParticipantId != null, '생성 모드에는 myParticipantId가 필요합니다.');
      assert(character == null, '생성 모드에는 character가 null이어야 합니다.');
      participantId = myParticipantId!;
    } else {
      assert(character != null, '수정 모드에는 character가 필요합니다.');
      participantId = character!.participantId;
    }

    // ✅ [중요] 모달을 띄우기 전, 현재 context에서 provider를 읽어옵니다.
    final provider = context.read<RoomDataProvider>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // 시트가 화면의 많은 부분을 차지하도록 함
      builder: (ctx) {
        // ✅ [중요] 모달에 provider를 주입합니다.
        return ChangeNotifierProvider.value(
          value: provider,
          child: CharacterSheetEditorModal(
            mode: editorMode,
            systemId: systemId,
            participantId: participantId,
            character: character,
          ),
        );
      },
    );
  }
}