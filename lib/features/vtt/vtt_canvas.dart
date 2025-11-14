import 'dart:math';
import 'dart:typed_data'; // [신규] S3 업로드를 위해 추가
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart'; // [신규] 이미지 피커
import 'package:http/http.dart' as http; // [신규] S3 업로드용

import 'package:trpg_frontend/models/token.dart';
import 'package:trpg_frontend/models/vtt_scene.dart';
import 'package:trpg_frontend/models/map_asset.dart'; // [신규] MapAsset 모델
import 'package:trpg_frontend/services/vtt_socket_service.dart';
import 'package:trpg_frontend/services/token_service.dart';
import 'package:trpg_frontend/services/vtt_service.dart'; // [신규] VttService (API 호출용)

class VttCanvas extends StatefulWidget {
  const VttCanvas({super.key});

  @override
  State<VttCanvas> createState() => _VttCanvasState();
}

class _VttCanvasState extends State<VttCanvas> {
  late TransformationController _transformationController;

  static const double _defaultCanvasWidth = 2000.0;
  static const double _defaultCanvasHeight = 2000.0;

  static final Matrix4 _defaultCenterMatrix = Matrix4.identity()
    ..translate(-_defaultCanvasWidth / 4, -_defaultCanvasHeight / 4);

  // 현재 씬 ID를 추적
  String? _currentSceneId;
  bool _isInteracting = false;


  VttScene? _lastProcessedScene;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController(_defaultCenterMatrix);
    
    // [수정 2] 'read'로 초기값만 가져옴
    final initialScene = context.read<VttSocketService>().scene;
    _currentSceneId = initialScene?.id;
    _lastProcessedScene = initialScene; // [수정 2] 마지막 씬 기록

    // [수정 2] 앱 시작 시 씬이 있다면 "즉시" 컨트롤러 위치를 설정
    if (initialScene != null) {
      _syncControllerWithScene(initialScene, runImmediately: true);
    }
    context.read<VttSocketService>().registerUploadImageHandler(_handleImageUpload);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final vttSocket = context.watch<VttSocketService>();
    final newScene = vttSocket.scene;

    // [수정 3] 씬 객체 인스턴스가 실제로 변경되었을 때만 동기화
    if (newScene != _lastProcessedScene) {
      _syncControllerWithScene(newScene);
      _lastProcessedScene = newScene; // 마지막으로 처리한 씬을 기록
    }
  }

  /// [최종 수정] 맵/씬의 상태 변화에 따라 컨트롤러를 동기화하는 로직
  /// [수정됨] 맵/씬의 상태 변화에 따라 컨트롤러를 동기화하는 로직
  /// runImmediately 플래그가 추가되어, initState에서도 호출할 수 있습니다.
  void _syncControllerWithScene(VttScene? scene, {bool runImmediately = false}) {
    // 1. 사용자가 캔버스를 조작 중(드래그/줌)일 때는 덮어쓰기 방지
    if (_isInteracting) return;

    // 씬에 저장된 위치/축척 값이 있는지 확인 (부동소수점 오차 감안)
    final bool isSceneSaved = scene != null &&
        (scene.imageX.abs() > 0.001 ||
            scene.imageY.abs() > 0.001 ||
            (scene.imageScale - 1.0).abs() > 0.001);

    // 2. 씬 ID가 변경되었는가? (맵 입장/퇴장/변경)
    if (scene?.id != _currentSceneId) {
      _currentSceneId = scene?.id; // 씬 ID 즉시 업데이트
      Matrix4 targetMatrix;

      if (scene == null) {
        // 2a. 씬이 없음 (맵에서 나감) -> 중앙으로
        targetMatrix = _defaultCenterMatrix;
      } else if (isSceneSaved) {
        // 2b. '저장된 맵'에 입장 -> 맵 데이터로
        targetMatrix = Matrix4.identity()
          ..translate(scene.imageX, scene.imageY)
          ..scale(scene.imageScale);
      } else {
        // 2c. '새 맵'(0,0,1)에 입장 -> 중앙으로
        targetMatrix = _defaultCenterMatrix;
      }

      // 맵이 바뀌었으니 컨트롤러 값을 업데이트
      // 🚨 [수정] runImmediately 플래그를 전달합니다.
      _updateControllerValue(targetMatrix, runImmediately: runImmediately);
      return; // 맵 변경 로직 끝
    }

    // 3. 씬 ID가 같다 (같은 맵에 머무는 중)
    if (scene != null && isSceneSaved) {
      // 3a. '저장된 맵'에 머무는 중:
      // 다른 유저가 맵을 움직였을 수 있으니 동기화
      final Matrix4 sceneMatrix = Matrix4.identity()
        ..translate(scene.imageX, scene.imageY)
        ..scale(scene.imageScale);
      
      // 🚨 [수정] runImmediately 플래그를 전달합니다.
      _updateControllerValue(sceneMatrix, runImmediately: runImmediately);
    }
    // 3b. '새 맵'(0,0,1)에 머무는 중 (isSceneSaved == false):
    //    -> 🚨 아무것도 하지 않는다!
  }

  /// [신규] 빌드 사이클과 충돌하지 않도록 안전하게 컨트롤러 값을 업데이트
void _updateControllerValue(Matrix4 targetMatrix, {bool runImmediately = false}) {
    
    // 1. 실제 컨트롤러 값을 변경하는 로직을 변수로 분리
    void updateLogic() {
      // [수정] 소수점 정밀도 문제로 인한 무한 루프 방지를 위해 toString() 비교
      if (mounted &&
          _transformationController.value.toString() != targetMatrix.toString()) {
        _transformationController.value = targetMatrix;
      }
    }

    // 2. 🚨 [수정] 플래그에 따라 실행 방식을 분기
    if (runImmediately) {
      // initState에서 호출될 때: 즉시 실행
      updateLogic();
    } else {
      // didChangeDependencies에서 호출될 때: 프레임 끝난 후 실행 (무한 루프 방지)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        updateLogic();
      });
    }
  }

  void _onInteractionStart(ScaleStartDetails details) {
    // 🚨 [수정] setState() 제거
    // setState(() {
    //   _isInteracting = true;
    // });
    _isInteracting = true;
  }

  void _onInteractionEnd(ScaleEndDetails details, VttSocketService vttSocket) {
    // 🚨 [수정] setState() 제거 (스냅백 현상의 핵심 원인)
    // setState(() {
    //   _isInteracting = false;
    // });
    _isInteracting = false;

    final matrix = _transformationController.value;
    final double newScale = matrix.row0[0];
    final double newX = matrix.getTranslation().x;
    final double newY = matrix.getTranslation().y;

    final currentScene = vttSocket.scene;
    if (currentScene == null) return;

    final updatedScene = currentScene.copyWith(
      imageScale: newScale,
      imageX: newX,
      imageY: newY,
    );

    vttSocket.sendMapUpdate(updatedScene);
    debugPrint('Interaction End: Scale=$newScale, X=$newX, Y=$newY');
  }

  // --- [신규] 이미지 업로드 로직 (요구사항 1, 2) ---
  Future<void> _handleImageUpload() async {
    if (!mounted) return;
    final vttSocket = context.read<VttSocketService>();
    final scene = vttSocket.scene;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (scene == null) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('이미지를 업로드할 맵을 먼저 선택해주세요.')),
      );
      return;
    }

    // 1. 이미지 선택
    final picker = ImagePicker();
    final XFile? imageFile;
    try {
      imageFile = await picker.pickImage(source: ImageSource.gallery);
      if (imageFile == null) return; // 사용자가 취소
    } catch (e) {
      debugPrint("Image picking failed: $e");
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('이미지 선택에 실패했습니다: $e')),
      );
      return;
    }

    context.read<VttSocketService>().setIsUploading(true);

    try {
      // 2. Presigned URL 요청
      final String extension = imageFile.name.split('.').last.toLowerCase();
      // (vtt_service.dart에 getUploadPresignedUrl 구현 필요)
      final String presignedUrl =
          await VttService.instance.getUploadPresignedUrl(vttSocket.roomId, extension);

      // 3. S3로 파일 업로드
      final Uint8List fileBytes = await imageFile.readAsBytes();
      final uri = Uri.parse(presignedUrl);
      final response = await http.put(
        uri,
        body: fileBytes,
        headers: {
          'Content-Type': 'image/$extension', // MIME 타입 설정
        },
      );

      if (response.statusCode != 200) {
        throw Exception('S3 업로드 실패: ${response.statusCode}');
      }

      // 4. 백엔드에 MapAsset 생성 요청 (요구사항 2: 캔버스 중앙)
      final String finalImageUrl = uri.origin + uri.path;

      // 현재 뷰포트의 중앙 좌표를 캔버스 좌표로 변환
      if (!mounted) return;
      final Size viewportSize = MediaQuery.of(context).size;
      final Matrix4 matrix = _transformationController.value;
      final double currentScale = matrix.row0[0];
      final double currentX = matrix.getTranslation().x;
      final double currentY = matrix.getTranslation().y;

      // 뷰포트 중심의 캔버스 좌표
      final double centerXInCanvas = (viewportSize.width / 2 - currentX) / currentScale;
      final double centerYInCanvas = (viewportSize.height / 2 - currentY) / currentScale;
      
      const double defaultWidth = 200.0;
      const double defaultHeight = 200.0;

      // (vtt_service.dart에 createMapAsset 구현 필요)
      await VttService.instance.createMapAsset(
        scene.id,
        finalImageUrl,
        centerXInCanvas - (defaultWidth / 2), // 중앙 정렬
        centerYInCanvas - (defaultHeight / 2), // 중앙 정렬
        defaultWidth,
        defaultHeight,
      );

      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('이미지 업로드 성공!'), backgroundColor: Colors.green),
      );

    } catch (e) {
      debugPrint("Image upload process failed: $e");
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('이미지 업로드 실패: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        context.read<VttSocketService>().setIsUploading(false);
      }
    }
  }
  // --- [신규 끝] ---

  @override
  Widget build(BuildContext context) {
    final vttSocket = context.read<VttSocketService>();
    final scene = vttSocket.scene;
    final tokens = vttSocket.tokens.values.toList();
    // --- [신규] MapAsset 목록 가져오기 ---
    final mapAssets = vttSocket.mapAssets.values.toList();
    // --- [신규 끝] ---
    final isConnected = vttSocket.isConnected;

    // build가 실행될 때마다(상태 변경 시) 동기화 함수 호출
    // _syncControllerWithScene(scene);

    if (!isConnected) {
      return const Center(child: Text('VTT 서버에 연결 중...'));
    }

    final VttScene effectiveScene = scene ??
        VttScene(
          id: 'default_empty_canvas',
          roomId: vttSocket.roomId,
          name: 'Empty Canvas',
          backgroundUrl: null,
          gridType: 'square',
          gridSize: 50,
          showGrid: true,
          imageScale: 1.0,
          imageX: 0.0,
          imageY: 0.0,
          localWidth: _defaultCanvasWidth.toInt(),
          localHeight: _defaultCanvasHeight.toInt(),
          isActive: false,
          properties: {
            'gridColor': '0x80000000',
            'gridOpacity': 0.2,
          },
        );

    final List<Token> effectiveTokens = (scene != null) ? tokens : [];
    // --- [신규] MapAsset 목록 ---
    final List<MapAsset> effectiveMapAssets = (scene != null) ? mapAssets : [];
    // --- [신규 끝] ---

    return InteractiveViewer(
      transformationController: _transformationController,
      onInteractionStart: _onInteractionStart,
      onInteractionEnd: (scene != null)
          ? (details) => _onInteractionEnd(details, vttSocket)
          : null,
      minScale: 0.1,
      maxScale: 10.0,
      constrained: false,
      child: SizedBox( // 👈 1. Stack을 SizedBox로 감쌉니다.
        // 2. SizedBox에 유한한 크기를 줍니다.
        width: effectiveScene.localWidth.toDouble(),
        height: effectiveScene.localHeight.toDouble(),
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          // Layer 1: 배경 이미지
          Positioned(
            left: 0,
            top: 0,
            width: effectiveScene.localWidth.toDouble(),
            height: effectiveScene.localHeight.toDouble(),
            child: _buildBackgroundImage(effectiveScene),
          ),

          // Layer 2: 그리드
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(
                showGrid: effectiveScene.showGrid,
                gridSize: effectiveScene.gridSize.toDouble(),
                gridColor: Color(int.tryParse(
                        effectiveScene.properties['gridColor'] ?? '0xFF000000') ??
                    0xFF000000),
                gridOpacity:
                    (effectiveScene.properties['gridOpacity'] as num?)?.toDouble() ??
                        0.5,
              ),
            ),
          ),

          // --- [신규] Layer 2.5: 맵 에셋(이미지) 목록 ---
          // 토큰보다 아래에 렌더링
          ...effectiveMapAssets.map(
            (asset) => _MapAssetItem(
              key: ValueKey(asset.id),
              asset: asset,
              transformationController: _transformationController,
              onPositionChanged: (newX, newY) {
                // (vtt_socket_service.dart에 sendUpdateMapAsset 구현 필요)
                vttSocket.sendUpdateMapAsset(
                  asset.id, newX, newY, asset.width, asset.height
                );
              },
              onSizeChanged: (newWidth, newHeight) {
                // (vtt_socket_service.dart에 sendUpdateMapAsset 구현 필요)
                 vttSocket.sendUpdateMapAsset(
                  asset.id, asset.x, asset.y, newWidth, newHeight
                );
              },
              onDelete: () {
                // (vtt_socket_service.dart에 sendDeleteMapAsset 구현 필요)
                vttSocket.sendDeleteMapAsset(asset.id);
              }
            ),
          ),
          // --- [신규 끝] ---

          // Layer 3: 토큰 목록
          ...effectiveTokens.map(
            (token) => _TokenItem(
              key: ValueKey(token.id),
              token: token,
              transformationController: _transformationController,
              onPositionChanged: (newX, newY) {
                vttSocket.moveToken(token.id, newX, newY);
              },
              onSizeChanged: (newWidth, newHeight) {
                debugPrint(
                    '[Canvas] Token ${token.id} size changed: $newWidth x $newHeight');
                TokenService.instance.updateToken(
                  token.id,
                  width: newWidth,
                  height: newHeight,
                ).catchError((e) {
                  debugPrint('[Canvas] Token size update error: $e');
                });
              },
            ),
          ),

          // --- [신규] Layer 4: 이미지 업로드 버튼 ---
          
          // --- [신규 끝] ---

          // --- [신규] Layer 5: 업로드 로딩 오버레이 ---
          if (context.watch<VttSocketService>().isUploading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.5),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('이미지 업로드 중...', style: TextStyle(color: Colors.white, fontSize: 16)),
                    ],
                  ),
                ),
              ),
            ),
          // --- [신규 끝] ---
        ],
      ),
      ),
    );
  }

  /// 배경 이미지를 렌더링하는 위젯
  Widget _buildBackgroundImage(VttScene scene) {
    if (scene.backgroundUrl == null || scene.backgroundUrl!.isEmpty) {
      return Container(color: Colors.white);
    }

    return CachedNetworkImage(
      imageUrl: scene.backgroundUrl!,
      fit: BoxFit.fill,
      placeholder: (context, url) =>
          const Center(child: CircularProgressIndicator()),
      errorWidget: (context, url, error) =>
          const Center(child: Icon(Icons.error, color: Colors.red)),
    );
  }
}

// --- 🚨 [수정됨] (기능 2) 크기 조절을 위해 StatefulWidget으로 변경 ---
class _TokenItem extends StatefulWidget {
  final Token token;
  final TransformationController transformationController;
  final void Function(double newX, double newY) onPositionChanged;
  final void Function(double newWidth, double newHeight) onSizeChanged;

  const _TokenItem({
    super.key,
    required this.token,
    required this.transformationController,
    required this.onPositionChanged,
    required this.onSizeChanged,
  });

  @override
  State<_TokenItem> createState() => _TokenItemState();
}

class _TokenItemState extends State<_TokenItem> {
  // 크기/위치 조절 상태 관리를 위한 변수
  late double _currentWidth;
  late double _currentHeight;
  late double _currentX;
  late double _currentY;

  // [신규] 크기 조절 제스처 시작 시점의 크기
  double _initialWidth = 0;
  double _initialHeight = 0;

  @override
  void initState() {
    super.initState();
    _currentWidth = widget.token.width;
    _currentHeight = widget.token.height;
    _currentX = widget.token.x;
    _currentY = widget.token.y;
  }

  // [신규] 부모 위젯(Token 모델)이 변경될 때 내부 상태도 업데이트
  // (다른 유저가 토큰을 움직이거나 크기를 변경했을 때)
  @override
  void didUpdateWidget(covariant _TokenItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.token.width != oldWidget.token.width ||
        widget.token.height != oldWidget.token.height ||
        widget.token.x != oldWidget.token.x ||
        widget.token.y != oldWidget.token.y) {
      setState(() {
        _currentWidth = widget.token.width;
        _currentHeight = widget.token.height;
        _currentX = widget.token.x;
        _currentY = widget.token.y;
      });
    }
  }

  /// 캔버스의 현재 줌 배율을 가져옵니다.
  double get _currentMapScale =>
      widget.transformationController.value.row0[0];

  @override
  Widget build(BuildContext context) {
    return Positioned(
      // [수정] Positioned가 로컬 상태(_currentX/Y)를 따르도록 하여
      // 드래그 시 즉각적인 UI 반응을 보장 (Optimistic Update)
      left: _currentX,
      top: _currentY,
      // [수정] Token 모델의 width/height 사용
      width: _currentWidth,
      height: _currentHeight,
      child: Stack(
        clipBehavior: Clip.none, // 핸들이 밖으로 나가도 보이도록
        children: [
          // --- 1. 토큰 본체 (드래그하여 '이동') ---
          GestureDetector(
            onPanUpdate: (details) {
              // 맵 스케일을 보정하여 이동 거리 계산
              final double dx = details.delta.dx / _currentMapScale;
              final double dy = details.delta.dy / _currentMapScale;

              setState(() {
                _currentX += dx;
                _currentY += dy;
              });
            },
            onPanEnd: (details) {
              // 이동이 끝나면 서버에 최종 위치 전송
              widget.onPositionChanged(_currentX, _currentY);
            },
            child: Tooltip(
              message: widget.token.name,
              child: Opacity(
                opacity: widget.token.isVisible ? 0.95 : 0.4,
                child: Container(
                  width: double.infinity, // 부모 Positioned의 크기를 따름
                  height: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4.0), // 사각 토큰
                    border: Border.all(color: Colors.black45, width: 1.5),
                    color: Colors.blueGrey[100],
                    image: (widget.token.imageUrl != null &&
                            widget.token.imageUrl!.isNotEmpty)
                        ? DecorationImage(
                            image: CachedNetworkImageProvider(
                                widget.token.imageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        spreadRadius: 1,
                        blurRadius: 3,
                        offset: const Offset(1, 2),
                      ),
                    ],
                  ),
                  child: (widget.token.imageUrl == null ||
                          widget.token.imageUrl!.isEmpty)
                      ? Center(
                          child: Text(
                            widget.token.name.isNotEmpty
                                ? widget.token.name[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize:
                                  max(12.0, min(_currentWidth, _currentHeight) * 0.6),
                              color: Colors.black87,
                            ),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),

          // --- 🚨 [신규] 2. 크기 조절 핸들 (드래그하여 '크기 조절') ---
          Positioned(
            right: -8, // 잡기 쉽도록 토큰 밖으로 살짝 뺌
            bottom: -8,
            child: GestureDetector(
              onScaleStart: (details) {
                // 제스처 시작 시점의 크기를 저장
                _initialWidth = _currentWidth;
                _initialHeight = _currentHeight;
              },
              onScaleUpdate: (details) {
                // 제스처의 배율(scale)을 시작 크기에 곱하여 새 크기 계산
                // (비율 유지를 위해 동일한 배율 사용)
                setState(() {
                  _currentWidth = _initialWidth * details.scale;
                  _currentHeight = _initialHeight * details.scale;

                  // 최소 크기 제한
                  if (_currentWidth < 20) _currentWidth = 20;
                  if (_currentHeight < 20) _currentHeight = 20;
                });
              },
              onScaleEnd: (details) {
                // 크기 조절이 끝나면 서버에 최종 크기 전송
                widget.onSizeChanged(_currentWidth, _currentHeight);
              },
              // 이동(Pan) 제스처가 메인 토큰으로 전달되지 않도록 막음
              onPanUpdate: (details) {},
              child: Container(
                width: 24, // 핸들 크기
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.8),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child:
                    const Icon(Icons.zoom_out_map, size: 14, color: Colors.white),
              ),
            ),
          ),
          // --- 🚨 [신규 끝] ---
        ],
      ),
    );
  }
}
// --- 🚨 [수정 끝] ---

// --- [신규] MapAsset 렌더링 및 상호작용 위젯 (요구사항 3) ---
class _MapAssetItem extends StatefulWidget {
  final MapAsset asset;
  final TransformationController transformationController;
  final void Function(double newX, double newY) onPositionChanged;
  final void Function(double newWidth, double newHeight) onSizeChanged;
  final VoidCallback onDelete;

  const _MapAssetItem({
    super.key,
    required this.asset,
    required this.transformationController,
    required this.onPositionChanged,
    required this.onSizeChanged,
    required this.onDelete,
  });

  @override
  State<_MapAssetItem> createState() => _MapAssetItemState();
}

class _MapAssetItemState extends State<_MapAssetItem> {
  late double _currentWidth;
  late double _currentHeight;
  late double _currentX;
  late double _currentY;

  double _initialWidth = 0;
  double _initialHeight = 0;

  @override
  void initState() {
    super.initState();
    _currentWidth = widget.asset.width;
    _currentHeight = widget.asset.height;
    _currentX = widget.asset.x;
    _currentY = widget.asset.y;
  }

  @override
  void didUpdateWidget(covariant _MapAssetItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 다른 유저에 의해 변경되었을 때 로컬 상태 동기화
    if (widget.asset.width != oldWidget.asset.width ||
        widget.asset.height != oldWidget.asset.height ||
        widget.asset.x != oldWidget.asset.x ||
        widget.asset.y != oldWidget.asset.y) {
      setState(() {
        _currentWidth = widget.asset.width;
        _currentHeight = widget.asset.height;
        _currentX = widget.asset.x;
        _currentY = widget.asset.y;
      });
    }
  }

  double get _currentMapScale =>
      widget.transformationController.value.row0[0];

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _currentX,
      top: _currentY,
      width: _currentWidth,
      height: _currentHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // --- 1. 에셋 본체 (드래그하여 '이동') ---
          GestureDetector(
            onPanUpdate: (details) {
              final double dx = details.delta.dx / _currentMapScale;
              final double dy = details.delta.dy / _currentMapScale;
              setState(() {
                _currentX += dx;
                _currentY += dy;
              });
            },
            onPanEnd: (details) {
              widget.onPositionChanged(_currentX, _currentY);
            },
            child: Opacity(
              opacity: 0.9, // 토큰과 구분을 위해 살짝 투명도
              child: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.transparent, width: 0), // 선택 시 테두리 표시 가능
                ),
                child: CachedNetworkImage(
                  imageUrl: widget.asset.url,
                  fit: BoxFit.fill,
                  placeholder: (context, url) =>
                      Container(color: Colors.grey[300]),
                  errorWidget: (context, url, error) =>
                      const Icon(Icons.broken_image, color: Colors.red),
                ),
              ),
            ),
          ),

          // --- 2. 크기 조절 핸들 (드래그하여 '크기 조절') ---
          Positioned(
            right: -8,
            bottom: -8,
            child: GestureDetector(
              onScaleStart: (details) {
                _initialWidth = _currentWidth;
                _initialHeight = _currentHeight;
              },
              onScaleUpdate: (details) {
                setState(() {
                  _currentWidth = _initialWidth * details.scale;
                  _currentHeight = _initialHeight * details.scale;
                  if (_currentWidth < 20) _currentWidth = 20;
                  if (_currentHeight < 20) _currentHeight = 20;
                });
              },
              onScaleEnd: (details) {
                widget.onSizeChanged(_currentWidth, _currentHeight);
              },
              onPanUpdate: (details) {}, // 메인 이동 제스처 방해 방지
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.8),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.zoom_out_map, size: 14, color: Colors.white),
              ),
            ),
          ),

           // --- 3. 삭제 핸들 ---
          Positioned(
            left: -8,
            bottom: -8,
            child: GestureDetector(
              onTap: () {
                 // 삭제 확인 다이얼로그를 띄우는 것이 좋지만, 우선 즉시 삭제
                 widget.onDelete();
              },
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.8),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.delete, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// --- [신규 끝] ---


/// [신규] 맵 그리드를 그리는 CustomPainter
class _GridPainter extends CustomPainter {
  final bool showGrid;
  final double gridSize;
  final Color gridColor;
  final double gridOpacity;

  _GridPainter({
    required this.showGrid,
    required this.gridSize,
    required this.gridColor,
    required this.gridOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!showGrid || gridSize <= 0) return;

    final paint = Paint()
      ..color = gridColor.withOpacity(gridOpacity)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // 세로선
    for (double x = 0; x <= size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // 가로선
    for (double y = 0; y <= size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.showGrid != showGrid ||
        oldDelegate.gridSize != gridSize ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.gridOpacity != gridOpacity;
  }
}