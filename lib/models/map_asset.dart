import 'package:flutter/foundation.dart'; // For debugPrint

/// 백엔드의 MapAsset 엔티티/DTO에 대응하는 모델
/// VTT 캔버스에 업로드된 (배경/소품) 이미지를 나타냅니다.
class MapAsset {
  final String id; // MapAsset ID (UUID)
  final String mapId; // VttMap ID (UUID)
  final String url; // S3에 업로드된 이미지 주소

  double x, y; // Position (mutable)
  double width; // Image width (mutable)
  double height; // Image height (mutable)

  MapAsset({
    required this.id,
    required this.mapId,
    required this.url,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// 백엔드 REST API 또는 WebSocket의 JSON 응답을 MapAsset 객체로 변환합니다.
  factory MapAsset.fromJson(Map<String, dynamic> j) {
    // Helper to safely parse double
    double _parseDouble(dynamic value, {double defaultValue = 0.0}) {
      if (value == null) return defaultValue;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    // Safely parse required fields
    final id = j['id']?.toString();
    final mapId = j['mapId']?.toString();
    final url = j['url'] as String?;
    final x = _parseDouble(j['x']);
    final y = _parseDouble(j['y']);

    // 기본 크기를 100.0으로 설정 (토큰보다 클 수 있음을 가정)
    final width = _parseDouble(j['width'], defaultValue: 100.0);
    final height = _parseDouble(j['height'], defaultValue: 100.0);

    // Validate required fields
    if (id == null) {
      throw FormatException("Invalid or missing 'id' in MapAsset JSON: $j");
    }
    if (mapId == null) {
      debugPrint("Problematic MapAsset JSON for mapId: $j");
      throw FormatException("Invalid or missing 'mapId' in MapAsset JSON: $j");
    }
    if (url == null) {
      throw FormatException("Invalid or missing 'url' in MapAsset JSON: $j");
    }

    return MapAsset(
      id: id,
      mapId: mapId,
      url: url,
      x: x,
      y: y,
      width: width,
      height: height,
    );
  }

  /// MapAsset 객체를 JSON으로 변환합니다.
  Map<String, dynamic> toJson() => {
        'id': id,
        'mapId': mapId,
        'url': url,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  /// 객체 복사를 위한 copyWith 메서드
  MapAsset copyWith({
    String? id,
    String? mapId,
    String? url,
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    return MapAsset(
      id: id ?? this.id,
      mapId: mapId ?? this.mapId,
      url: url ?? this.url,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}