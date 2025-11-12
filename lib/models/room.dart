// lib/models/room.dart
import 'participant.dart';

class Room {
  final String? id; // TRPG Room UUID
  final String name;
  final String? password;
  final int maxParticipants;
  final int currentParticipants;
  final List<Participant> participants;
  final int? creatorId;
  final String trpgType; // ✅ 1. 'system'에서 'trpgType'으로 필드명 변경
  final int? chatRoomId; 

  Room({
    this.id,
    required this.name,
    this.password,
    required this.maxParticipants,
    this.currentParticipants = 0,
    this.participants = const [],
    this.creatorId,
    required this.trpgType, // ✅ 2. 생성자 파라미터 변경 (system -> trpgType)
    this.chatRoomId, 
  });

  Map<String, dynamic> toCreateJson() {
    final json = <String, dynamic>{
      'name': name,
      'maxParticipants': maxParticipants,
      'system': trpgType, // ✅ 3. JSON 키는 'system'을 유지, 값은 'trpgType' 사용
    };

    // 로컬 변수에 할당 → promotion 가능
    final pwd = password;
    if (pwd != null && pwd.isNotEmpty) {
      json['password'] = pwd;
    }

    return json;
  }

  factory Room.fromJson(Map<String, dynamic> json) {
    // 백엔드 응답이 { message: '...', room: {...} } 형태일 수 있으므로 data 키 확인
    final data = json['room'] is Map<String, dynamic> ? json['room'] : json;

    final participants = (data['participants'] as List<dynamic>?)
            ?.map((e) => Participant.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return Room(
      id: data['id']?.toString(), // TRPG Room UUID
      name: data['name'] as String? ?? 'no_name',
      password: data['password'] as String?,
      maxParticipants: data['maxParticipants'] as int? ?? 0,
      currentParticipants: data['currentParticipants'] as int? ?? 0,
      participants: participants,
      creatorId: data['creatorId'] as int?,
      trpgType: data['system'] as String? ?? 'coc7e', // ✅ 4. 'system' 키에서 읽어 'trpgType'에 할당
      chatRoomId: data['chat_room_id'] as int?, 
    );
  }

  bool get isValid =>
      name.isNotEmpty &&
      maxParticipants > 0 &&
      maxParticipants >= currentParticipants;

  bool get canJoin => currentParticipants < maxParticipants;

  Room copyWith({
    String? id,
    String? name,
    String? password,
    int? maxParticipants,
    int? currentParticipants,
    List<Participant>? participants,
    int? creatorId,
    String? trpgType, // ✅ 5. copyWith 파라미터 변경 (system -> trpgType)
    int? chatRoomId, 
  }) {
    return Room(
      id: id ?? this.id,
      name: name ?? this.name,
      password: password ?? this.password,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      currentParticipants: currentParticipants ?? this.currentParticipants,
      participants: participants ?? this.participants,
      creatorId: creatorId ?? this.creatorId,
      trpgType: trpgType ?? this.trpgType, // ✅ 6. copyWith 로직 변경 (system -> trpgType)
      chatRoomId: chatRoomId ?? this.chatRoomId, 
    );
  }
}