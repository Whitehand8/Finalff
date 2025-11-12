class Participant {
  final int id;
  final int userId;
  final String nickname;
  final String role;
  final String name;

  Participant({
    required this.id,
    required this.userId,
    required this.nickname,
    required this.name,
    required this.role,
  });

  factory Participant.fromJson(Map<String, dynamic> json) {
    return Participant(
      id: json['id'] as int,
      userId: json['userId'] as int,
      nickname: json['nickname'] as String,
      name: json['name'] as String,
      role: json['role'] as String,
    );
  }
}
