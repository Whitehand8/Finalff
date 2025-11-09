import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:trpg_frontend/models/token.dart';
import 'package:trpg_frontend/models/vtt_scene.dart';
import 'package:trpg_frontend/services/vtt_socket_service.dart';
import 'package:trpg_frontend/services/token_service.dart'; 

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

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController(_defaultCenterMatrix);
    final initialScene = context.read<VttSocketService>().scene;
    _currentSceneId = initialScene?.id;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  /// [수정] 맵/씬의 상태 변화에 따라 컨트롤러를 동기화하는 로직
  void _syncControllerWithScene(VttScene? scene) {
    // 1. 사용자가 캔버스를 조작 중(드래그/줌)일 때는 덮어쓰기 방지
    if (_isInteracting) return;

    Matrix4 targetMatrix; // 이 빌드에서 컨트롤러가 가져야 할 목표 매트릭스

    // bool isSceneSaved = scene != null &&
    //     (scene.imageX != 0.0 || scene.imageY != 0.0 || scene.imageScale != 1.0);
    
    // [신규] 씬에 저장된 위치/축척 값이 있는지 확인
    final bool isSceneSaved = scene != null &&
        (scene.imageX.abs() > 0.001 || // 0.0과 정확히 비교하지 않음
         scene.imageY.abs() > 0.001 ||
         (scene.imageScale - 1.0).abs() > 0.001);


    if (scene == null) {
      // 2. 씬이 없음 (맵에서 나감) -> 무조건 중앙으로
      targetMatrix = _defaultCenterMatrix;
    } else {
      // 3. 씬이 있음
      if (isSceneSaved) {
        // 3a. '저장된 씬'(0,0,1 아님) -> 씬의 위치/축척으로 설정
        targetMatrix = Matrix4.identity()
          ..translate(scene.imageX, scene.imageY)
          ..scale(scene.imageScale);
      } else {
        // 3b. '새 씬'(0,0,1)이 로드됨
        // [핵심] 맵이 방금 바뀐 경우(_currentSceneId != scene.id)에만 중앙으로 리셋.
        // 이미 이 맵에 있는데(ID가 같음) 씬 정보가 (0,0,1)로 왔다면,
        // (예: 토큰 이동) 컨트롤러를 덮어쓰면 안 됨 (사용자 조작 보존).
        if (_currentSceneId != scene.id) {
          // 맵이 '새 맵'으로 방금 변경됨 -> 중앙으로
          targetMatrix = _defaultCenterMatrix;
        } else {
          // 이미 '새 맵'에 머무는 중 -> 컨트롤러 덮어쓰기 중지 (사용자 조작 허용)
          // [수정] 씬 ID가 같으면 현재 씬 ID를 업데이트할 필요 없음
          _currentSceneId = scene.id; // 이 라인은 사실상 불필요하나, 안정성을 위해 유지
          return; 
        }
      }
    }

    // 4. 씬 ID 업데이트 (맵이 변경된 경우에만)
    if (_currentSceneId != scene?.id) {
      _currentSceneId = scene?.id;
    }

    // 5. 계산된 목표(targetMatrix)와 현재 컨트롤러 값이 다를 때만 안전하게 업데이트
    _updateControllerValue(targetMatrix);
  }


  /// [신규] 빌드 사이클과 충돌하지 않도록 안전하게 컨트롤러 값을 업데이트
  void _updateControllerValue(Matrix4 targetMatrix) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // [수정] 소수점 정밀도 문제로 인한 무한 루프 방지를 위해 toString() 비교
      if (mounted && _transformationController.value.toString() != targetMatrix.toString()) {
        _transformationController.value = targetMatrix;
      }
    });
  }

  void _onInteractionStart(ScaleStartDetails details) {
    setState(() {
      _isInteracting = true;
    });
  }

  void _onInteractionEnd(ScaleEndDetails details, VttSocketService vttSocket) {
    setState(() {
      _isInteracting = false;
    });

    final matrix = _transformationController.value;
    final double newScale = matrix.row0[0];
    final double newX = matrix.getTranslation().x;
    final double newY = matrix.getTranslation().y;

    final currentScene = vttSocket.scene;
    if (currentScene == null) return;

    // [신규] 맵이 (0,0,1) 상태일 때 사용자가 움직인 경우,
    // (0,0,1)로 다시 되돌아가는 것을 막기 위해 값 보정
    final bool isSceneDefault = (currentScene.imageX.abs() < 0.001 &&
                                 currentScene.imageY.abs() < 0.001 &&
                                 (currentScene.imageScale - 1.0).abs() < 0.001);
                                 
    // 맵이 기본값(0,0,1)이고 사용자 조작도 (0,0,1)과 비슷하면 전송 안 함
    if (isSceneDefault && 
        (newX.abs() < 0.001 && newY.abs() < 0.001 && (newScale - 1.0).abs() < 0.001)) {
      return;
    }

    final updatedScene = currentScene.copyWith(
      imageScale: newScale,
      imageX: newX,
      imageY: newY,
    );
    
    vttSocket.sendMapUpdate(updatedScene);
    debugPrint('Interaction End: Scale=$newScale, X=$newX, Y=$newY');
  }

  @override
  Widget build(BuildContext context) {
    final vttSocket = context.watch<VttSocketService>();
    final scene = vttSocket.scene;
    final tokens = vttSocket.tokens.values.toList();
    final isConnected = vttSocket.isConnected;

    // [수정] build가 실행될 때마다(상태 변경 시) 동기화 함수 호출
    _syncControllerWithScene(scene);

    if (!isConnected) {
      return const Center(child: Text('VTT 서버에 연결 중...'));
    }

    final VttScene effectiveScene = scene ?? VttScene(
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


    return InteractiveViewer(
      transformationController: _transformationController,
      onInteractionStart: _onInteractionStart,
      onInteractionEnd: (scene != null)
          ? (details) => _onInteractionEnd(details, vttSocket)
          : null,
      minScale: 0.1,
      maxScale: 10.0,
      constrained: false, 
      child: SizedBox(
        width: effectiveScene.localWidth.toDouble(),
        height: effectiveScene.localHeight.toDouble(),
        child: Stack(
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
                  gridColor: Color(
                      int.tryParse(effectiveScene.properties['gridColor'] ?? '0xFF000000') ??
                          0xFF000000),
                  gridOpacity:
                      (effectiveScene.properties['gridOpacity'] as num?)?.toDouble() ??
                          0.5,
                ),
              ),
            ),

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
                  debugPrint('[Canvas] Token ${token.id} size changed: $newWidth x $newHeight');
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
  double get _currentMapScale => widget.transformationController.value.row0[0];

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
                    image: (widget.token.imageUrl != null && widget.token.imageUrl!.isNotEmpty)
                        ? DecorationImage(
                            image: CachedNetworkImageProvider(widget.token.imageUrl!),
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
                  child: (widget.token.imageUrl == null || widget.token.imageUrl!.isEmpty)
                      ? Center(
                          child: Text(
                            widget.token.name.isNotEmpty ? widget.token.name[0].toUpperCase() : '?',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: max(12.0, min(_currentWidth, _currentHeight) * 0.6),
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
                child: const Icon(Icons.zoom_out_map, size: 14, color: Colors.white),
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