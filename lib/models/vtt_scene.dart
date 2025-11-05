// lib/models/vtt_scene.dart

/// VTT 맵(씬)을 나타내는 모델
/// [수정됨] 백엔드 VttMap 엔티티/DTO와 완벽히 동기화
class VttScene {
  final String id;
  final String roomId;
  final String name;
  final String? backgroundUrl; // 백엔드의 'imageUrl'

  // --- 백엔드 VttMap 필드 ---
  final String gridType;  // 'square' 또는 'none'
  final int gridSize;    // 픽셀 단위 크기
  final bool showGrid;   // 그리드 표시 여부

  // --- [신규] 배경 이미지 변형 필드 ---
  final double imageScale;
  final double imageX;
  final double imageY;

  // --- 프론트엔드 전용 로컬 필드 (서버와 동기화 X) ---
  final int localWidth;  // 로컬 캔버스용 너비
  final int localHeight; // 로컬 캔버스용 높이
  final bool isActive;    // 현재 활성화된 씬인지 여부
  
  // [수정됨] 백엔드에 없는 로컬 전용 속성 (e.g., gridColor)
  final Map<String, dynamic> properties;

  VttScene({
    required this.id,
    required this.roomId,
    required this.name,
    this.backgroundUrl,
    required this.gridType,
    required this.gridSize,
    required this.showGrid,
    // [신규]
    required this.imageScale,
    required this.imageX,
    required this.imageY,
    // [수정됨] 로컬 필드
    this.localWidth = 1000,
    this.localHeight = 800,
    this.isActive = false,
    this.properties = const {},
  });

  /// 백엔드 JSON (VttMapDto, VttMapEntity 등)을 VttScene 객체로 변환
  factory VttScene.fromJson(Map<String, dynamic> j) {
    
    // 백엔드에 없는 로컬 전용 속성들 (e.g., gridColor)
    final props = (j['properties'] as Map?)?.cast<String, dynamic>() ?? {};
    if (j['gridColor'] != null) props['gridColor'] = j['gridColor'];
    if (j['gridOpacity'] != null) props['gridOpacity'] = j['gridOpacity'];

    return VttScene(
      id: j['id'] as String? ?? '',
      roomId: j['roomId'] as String? ?? '',
      name: j['name'] as String? ?? 'Scene',
      
      // [수정됨] 백엔드는 'imageUrl' 필드를 사용
      backgroundUrl: j['imageUrl'] as String?, 

      // --- 백엔드 필드 파싱 ---
      gridType: j['gridType'] as String? ?? 'square',
      gridSize: (j['gridSize'] as num?)?.toInt() ?? 50,
      showGrid: j['showGrid'] as bool? ?? true,

      // --- [신규] 새 기능 필드 파싱 (기본값 포함) ---
      imageScale: (j['imageScale'] as num?)?.toDouble() ?? 1.0,
      imageX: (j['imageX'] as num?)?.toDouble() ?? 0.0,
      imageY: (j['imageY'] as num?)?.toDouble() ?? 0.0,
      
      // --- 로컬 전용 필드 (서버 값 X) ---
      // [수정됨] 백엔드에 width/height/isActive가 없으므로 JSON에서 파싱하지 않음.
      // 필요시 로컬에서 별도 관리해야 함.
      localWidth: (j['width'] as num?)?.toInt() ?? 1000, // 이전 로직 유지
      localHeight: (j['height'] as num?)?.toInt() ?? 800, // 이전 로직 유지
      isActive: j['isActive'] as bool? ?? false, // 이전 로직 유지

      properties: props,
    );
  }

  /// 맵 업데이트(UpdateVttMapDto)를 위한 JSON
  /// [API] PATCH /vttmaps/:mapId
  /// [Socket] emit('updateMap', ...)
  Map<String, dynamic> toUpdateJson() {
    // [수정됨] 백엔드의 UpdateVttMapDto에 *실제로 있는* 필드만 전송
    return {
      'name': name,
      'imageUrl': backgroundUrl,
      'gridType': gridType,
      'gridSize': gridSize,
      'showGrid': showGrid,
      
      // [신규] 새 기능 필드 전송
      'imageScale': imageScale,
      'imageX': imageX,
      'imageY': imageY,
      
      // [제거됨] width, height, gridColor, gridOpacity 등은
      // 백엔드 UpdateVttMapDto에 없으므로 전송하지 않음.
    };
  }

  /// 새 맵 생성(CreateVttMapDto)을 위한 JSON
  /// [API] POST /rooms/:roomId/vttmaps
  Map<String, dynamic> toCreateJson() {
    // [수정됨] 백엔드의 CreateVttMapDto에 *실제로 있는* 필드만 전송
    return {
      'name': name,
      'imageUrl': backgroundUrl,
      'gridType': gridType,
      'gridSize': gridSize,
      'showGrid': showGrid,

      // [신규] 새 기능 필드 전송
      'imageScale': imageScale,
      'imageX': imageX,
      'imageY': imageY,
      
      // [제거됨] width, height, gridColor, gridOpacity 등은
      // 백엔드 CreateVttMapDto에 없으므로 전송하지 않음.
    };
    // roomId는 VttService의 API 경로로 전달됨
  }
}