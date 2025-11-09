import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trpg_frontend/models/character.dart';
import 'package:trpg_frontend/providers/room_data_provider.dart';

class CharacterListItem extends StatelessWidget {
  final Character character;
  final VoidCallback onTap;

  const CharacterListItem({
    super.key,
    required this.character,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // RoomDataProvider에 접근하여 소유자(Participant)의 이름을 찾습니다.
    final ownerName = context.select<RoomDataProvider, String>((provider) {
      try {
        // character.ownerId는 User ID입니다.
        // Participant.userId와 일치하는 Participant를 찾아 그 이름을 반환합니다.
        final ownerParticipant = provider.participants.firstWhere(
          (p) => p.userId == character.ownerId,
        );
        return ownerParticipant.name;
      } catch (e) {
        // 참여자를 찾을 수 없는 경우 (예: 데이터 동기화 문제)
        return '소유자 불명';
      }
    });

    // character.dart 모델에 name, age Getter가 있다고 가정합니다.
    // (이전 단계에서 추가하기로 계획했습니다.)
    final characterName = character.name;
    final characterAge = character.age;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: ListTile(
        leading: const CircleAvatar(
          // TODO: character.data['imageUrl']이 있다면 이미지 표시
          child: Icon(Icons.person_outline),
        ),
        title: Text(
          characterName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('소유자: $ownerName / 나이: $characterAge'),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}