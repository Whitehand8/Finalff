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
    this.localWidth = 4000,
    this.localHeight = 4000,
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
      localWidth: (j['width'] as num?)?.toInt() ?? 4000, 
      localHeight: (j['height'] as num?)?.toInt() ?? 4000, 
      isActive: j['isActive'] as bool? ?? false, 

      properties: props,
    );
  }

  /// 맵 업데이트(UpdateVttMapDto)를 위한 JSON
  Map<String, dynamic> toUpdateJson() {
    return {
      'name': name,
      'imageUrl': backgroundUrl,
      'gridType': gridType,
      'gridSize': gridSize,
      'showGrid': showGrid,
      'imageScale': imageScale,
      'imageX': imageX,
      'imageY': imageY,
      'width': localWidth,
      'height': localHeight,
    };
  }

  /// 새 맵 생성(CreateVttMapDto)을 위한 JSON
  Map<String, dynamic> toCreateJson() {
    return {
      'roomId': roomId,
      'name': name,
      'imageUrl': backgroundUrl,
      'gridType': gridType,
      'gridSize': gridSize,
      'showGrid': showGrid,
      'imageScale': imageScale,
      'imageX': imageX,
      'imageY': imageY,
      'width': localWidth,
      'height': localHeight,
    };
  }

  // --- 🚨 [신규] (기능 3)을 위한 copyWith 메서드 ---
  VttScene copyWith({
    String? id,
    String? roomId,
    String? name,
    String? backgroundUrl,
    String? gridType,
    int? gridSize,
    bool? showGrid,
    double? imageScale,
    double? imageX,
    double? imageY,
    int? localWidth,
    int? localHeight,
    bool? isActive,
    Map<String, dynamic>? properties,
  }) {
    return VttScene(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      name: name ?? this.name,
      backgroundUrl: backgroundUrl ?? this.backgroundUrl,
      gridType: gridType ?? this.gridType,
      gridSize: gridSize ?? this.gridSize,
      showGrid: showGrid ?? this.showGrid,
      imageScale: imageScale ?? this.imageScale,
      imageX: imageX ?? this.imageX,
      imageY: imageY ?? this.imageY,
      localWidth: localWidth ?? this.localWidth,
      localHeight: localHeight ?? this.localHeight,
      isActive: isActive ?? this.isActive,
      properties: properties ?? this.properties,
    );
  }
  // --- 🚨 [신규 끝] ---
}