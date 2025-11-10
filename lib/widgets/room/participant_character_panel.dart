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

        return Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- 1. 참여자 목록 ---
              _buildSectionHeader(context, '참여자', provider.participants.length),
              _buildParticipantList(context, provider),

              // --- 2. TODO: NPC 목록 (향후 구현) ---
            ],
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

  Widget _buildParticipantList(
      BuildContext context, RoomDataProvider provider) {
    final participants = provider.participants;

    return Expanded(
      child: ListView.builder(
        itemCount: participants.length,
        itemBuilder: (context, index) {
          final p = participants[index];
          return _buildParticipantTile(context, provider, p);
        },
      ),
    );
  }

  /// ── [수정됨] ──
  /// 참여자 타일 UI (시트가 있으면 CharacterListItem, 없으면 생성 버튼)
  Widget _buildParticipantTile(
    BuildContext context,
    RoomDataProvider provider,
    Participant p,
  ) {
    Character? character;
      try {
        character = provider.characters.firstWhere((c) => c.participantId == p.id);
      } catch (e) {
        character = null; // 일치하는 캐릭터가 없으면 null
      }
    final bool isMe = provider.myParticipant?.id == p.id;
    final bool isGM = (provider.myParticipant?.role == 'GM');

    if (character != null) {
      // 캐릭터 시트가 있음 (본인 또는 타인)
      // GM이거나, 내 시트이거나, 공개된 시트일 때만 조회/수정 가능
      final bool canView = isGM || isMe || character.isPublic;
      return CharacterListItem(
      character: character,
      // ▼▼▼ [수정 3] null 대신 빈 함수 () {} 전달 ▼▼▼
      onTap: canView
          ? () {
              _showEditorModal(
                context: context,
                mode: 'update', // 'update' 문자열 전달
                systemId: provider.roomSystemId,
                character: character, // 기존 캐릭터 데이터
              );
            }
          : () {}, // 탭 불가능 시 빈 함수 전달
      // ▲▲▲ 수정 3 끝 ▲▲▲
    );
  }

    if (isMe) {
      // 캐릭터 시트가 없고, 본인일 경우 -> 생성 버튼
      return _buildMyCharacterCreateButton(context, provider);
    }

    // 캐릭터 시트가 없고, 타인일 경우 -> 빈 공간
    return const SizedBox.shrink();
  }

  /// '내 캐릭터 시트 추가' 버튼
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

  /// ── [수정됨] ──
  /// 생성/수정 모달을 띄우는 함수 (로직 완성)
  void _showEditorModal({
    required BuildContext context,
    required String mode, // 'create' 또는 'update' 문자열
    required String systemId,
    Character? character, // 수정 모드일 때만 전달
    int? myParticipantId, // 생성 모드일 때만 전달
  }) {
    // ▼▼▼ [수정 2/2] 모달 호출 로직을 완성합니다. ▼▼▼

    final SheetEditorMode editorMode =
        (mode == 'create') ? SheetEditorMode.create : SheetEditorMode.update;

    // participantId 결정:
    // - 생성 모드: myParticipantId 사용
    // - 수정 모드: character!.participantId 사용 (character_service에서 이미 participantId를 사용함)
    final int participantId;
    if (editorMode == SheetEditorMode.create) {
      assert(myParticipantId != null, '생성 모드에는 myParticipantId가 필요합니다.');
      assert(character == null, '생성 모드에는 character가 null이어야 합니다.');
      participantId = myParticipantId!;
    } else {
      assert(character != null, '수정 모드에는 character가 필요합니다.');
      participantId = character!.participantId;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // 시트가 화면의 많은 부분을 차지하도록 함
      builder: (ctx) {
        // CharacterSheetEditorModal이 Scaffold를 포함하고 있으므로
        // 별도 패딩 없이 바로 위젯을 반환합니다.
        return CharacterSheetEditorModal(
          mode: editorMode,
          systemId: systemId,
          participantId: participantId,
          character: character,
        );
      },
    );
  }
}