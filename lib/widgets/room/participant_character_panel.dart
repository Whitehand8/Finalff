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
          // TODO: 이 패널을 DraggableScrollableSheet 등으로 감싸서
          // 드래그 가능한 창으로 만들 수 있습니다.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- 1. 참여자 목록 ---
              _buildSectionHeader(context, '참여자', provider.participants.length),
              _buildParticipantList(provider.participants),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              // --- 2. 캐릭터 시트 목록 ---
              _buildSectionHeader(
                  context, '캐릭터 시트', provider.characters.length),
              Expanded(child: _buildCharacterList(provider.characters)),

              const SizedBox(height: 12),

              // --- 3. 시트 추가 버튼 ---
              _buildAddSheetButton(context, provider),
            ],
          ),
        );
      },
    );
  }

  // 섹션 헤더 (예: "참여자 (3)")
  Widget _buildSectionHeader(BuildContext context, String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        '$title ($count)',
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }

  // 참여자 목록 UI
  Widget _buildParticipantList(List<Participant> participants) {
    // 캐릭터 시트 목록이 메인이므로, 참여자 목록은 간단하게 표시하거나
    // 고정된 높이를 부여합니다.
    return Container(
      height: 100, // 예시 높이, 스크롤 가능하도록 설정
      child: ListView.builder(
        itemCount: participants.length,
        itemBuilder: (context, index) {
          final participant = participants[index];
          return ListTile(
            dense: true,
            leading: Icon(participant.role == 'GM'
                ? Icons.shield_rounded
                : Icons.person_rounded),
            title: Text(participant.name),
            subtitle: Text(participant.role),
          );
        },
      ),
    );
  }

  // 캐릭터 시트 목록 UI
  Widget _buildCharacterList(List<Character> characters) {
    if (characters.isEmpty) {
      return const Center(child: Text('생성된 캐릭터 시트가 없습니다.'));
    }

    // TODO: 'CharacterListItem' 위젯 생성 후 아래 주석을 해제하세요.
    return ListView.builder(
      itemCount: characters.length,
      itemBuilder: (context, index) {
        final character = characters[index];
        // return CharacterListItem(
        //   character: character,
        //   onTap: () {
        //     _showEditorModal(
        //       context: context,
        //       mode: 'update',
        //       character: character,
        //       systemId: character.trpgType, // 기존 시트의 룰 ID
        //     );
        //   },
        // );

        // --- 임시 ---
        return ListTile(
          title: Text(character.data['name'] ?? '이름 없음'),
          subtitle: Text('Owner ID: ${character.ownerId}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            print('TODO: Open editor modal for ${character.id}');
          },
        );
        // --- 임시 ---
      },
    );
  }

  // '시트 추가' 버튼 UI
  Widget _buildAddSheetButton(BuildContext context, RoomDataProvider provider) {
    // 내 참가자 정보가 없으면 버튼을 비활성화
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

  // 생성/수정 모달을 띄우는 함수
  void _showEditorModal({
    required BuildContext context,
    required String mode,
    required String systemId,
    Character? character, // 수정 모드일 때만 전달
    int? myParticipantId, // 생성 모드일 때만 전달
  }) {
    // TODO: 'CharacterSheetEditorModal' 위젯 생성 후 아래 주석을 해제하세요.

     print('모달 열기: $mode, 시스템: $systemId');

     showModalBottomSheet(
       context: context,
       isScrollControlled: true, // 시트가 키보드를 가리지 않게 함
       builder: (ctx) {
         return Padding(
           // 키보드 높이만큼 패딩을 줘서 가려지는 현상 방지
           padding: EdgeInsets.only(
               bottom: MediaQuery.of(ctx).viewInsets.bottom),
           child: CharacterSheetEditorModal(
             mode: SheetEditorMode.create,
             systemId: systemId,
             character: character, // 수정 시 전달
             participantId: character?.participantId ??
                 myParticipantId!, // 수정/생성 시 ID
           ),
         );
       },
    );
  }
}