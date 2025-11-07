import 'package:flutter/foundation.dart'; // For debugPrint

/// 백엔드의 Token 엔티티/DTO에 대응하는 모델
class Token {
  final String id; // Token ID (UUID)
  final String mapId; // VttMap ID (UUID)

  // 연결된 시트 또는 NPC (둘 중 하나만 값을 가짐)
  final int? characterSheetId;
  final int? npcId; // Npc ID (number)

  String name;
  double x, y; // Position (mutable)
  
  // --- 🚨 [신규] 기능 2 (크기 편집)을 위한 필드 ---
  double width;  // Token width (mutable)
  double height; // Token height (mutable)
  // --- 🚨 [신규 끝] ---

  String? imageUrl; // Token image
  bool isVisible; // 토큰 표시 여부
  final bool canMove; // 현재 사용자가 이 토큰을 움직일 수 있는지 여부

  Token({
    required this.id,
    required this.mapId,
    this.characterSheetId,
    this.npcId,
    required this.name,
    required this.x,
    required this.y,
    // --- 🚨 [신규] 생성자에 width, height 추가 ---
    required this.width,
    required this.height,
    // --- 🚨 [신규 끝] ---
    this.imageUrl,
    this.isVisible = true,
    this.canMove = false, 
  });

  /// 백엔드 REST API 또는 WebSocket('joinedMap' 이벤트의 'Tokens' 배열)의
  /// JSON 응답을 Token 객체로 변환합니다.
  factory Token.fromJson(Map<String, dynamic> j) {
    // Helper to safely parse double
    double _parseDouble(dynamic value, {double defaultValue = 0.0}) { // 기본값 인자 추가
      if (value == null) return defaultValue;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    // Helper to safely parse int, returns null if parsing fails or input is null
    int? _parseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      if (value is double) return value.toInt();
      return null;
    }

    // Safely parse required fields
    final id = j['id']?.toString();
    final mapId = j['mapId']?.toString();
    final name = j['name'] as String? ?? 'Token'; // Default name
    final x = _parseDouble(j['x']);
    final y = _parseDouble(j['y']);

    // --- 🚨 [신규] width, height 파싱 (기본값 50.0) ---
    // 백엔드 DB의 기본값을 50.0으로 가정합니다.
    final width = _parseDouble(j['width'], defaultValue: 50.0);
    final height = _parseDouble(j['height'], defaultValue: 50.0);
    // --- 🚨 [신규 끝] ---

    // Validate required fields
    if (id == null) {
      throw FormatException("Invalid or missing 'id' in Token JSON: $j");
    }
    if (mapId == null) {
      debugPrint("Problematic Token JSON for mapId: $j");
      throw FormatException("Invalid or missing 'mapId' in Token JSON: $j");
    }

    return Token(
      id: id,
      mapId: mapId,
      characterSheetId: _parseInt(j['characterSheetId']),
      npcId: _parseInt(j['npcId']), 
      name: name,
      x: x,
      y: y,
      // --- 🚨 [신규] width, height 할당 ---
      width: width,
      height: height,
      // --- 🚨 [신규 끝] ---
      imageUrl: j['imageUrl'] as String?,
      isVisible: j['isVisible'] as bool? ?? true,
      canMove: j['canMove'] as bool? ?? false,
    );
  }

  /// Token 객체를 JSON으로 변환합니다.
  Map<String, dynamic> toJson() => {
        'id': id,
        'mapId': mapId,
        'characterSheetId': characterSheetId,
        'npcId': npcId,
        'name': name,
        'x': x,
        'y': y,
        // --- 🚨 [신규] toJson에 width, height 추가 ---
        'width': width,
        'height': height,
        // --- 🚨 [신규 끝] ---
        'imageUrl': imageUrl,
        'isVisible': isVisible,
        'canMove': canMove,
      };

  /// 객체 복사를 위한 copyWith 메서드
  Token copyWith({
    String? id,
    String? mapId,
    int? characterSheetId,
    int? npcId,
    String? name,
    double? x,
    double? y,
    // --- 🚨 [신규] copyWith에 width, height 추가 ---
    double? width,
    double? height,
    // --- 🚨 [신규 끝] ---
    String? imageUrl,
    bool? isVisible,
    bool? canMove,
  }) {
    return Token(
      id: id ?? this.id,
      mapId: mapId ?? this.mapId,
      characterSheetId: characterSheetId ?? this.characterSheetId,
      npcId: npcId ?? this.npcId,
      name: name ?? this.name,
      x: x ?? this.x,
      y: y ?? this.y,
      // --- 🚨 [신규] copyWith에 width, height 할당 ---
      width: width ?? this.width,
      height: height ?? this.height,
      // --- 🚨 [신규 끝] ---
      imageUrl: imageUrl ?? this.imageUrl,
      isVisible: isVisible ?? this.isVisible,
      canMove: canMove ?? this.canMove,
    );
  }
}