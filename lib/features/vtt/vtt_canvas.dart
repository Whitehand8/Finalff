import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:trpg_frontend/models/token.dart';
import 'package:trpg_frontend/models/vtt_scene.dart';
import 'package:trpg_frontend/services/vtt_socket_service.dart';
// [제거됨] VttService (REST API)는 토큰 이동에 사용하지 않습니다.
// import 'package:trpg_frontend/services/vtt_service.dart'; 

/// [수정됨] VttCanvas를 StatefulWidget으로 변경
/// - 배경 이미지의 이동/확대 상태를 관리하기 위해 TransformationController가 필요
class VttCanvas extends StatefulWidget {
  const VttCanvas({super.key});

  @override
  State<VttCanvas> createState() => _VttCanvasState();
}

class _VttCanvasState extends State<VttCanvas> {
  // InteractiveViewer를 제어하여 맵의 확대/축소/이동 상태를 관리
  late TransformationController _transformationController;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();

    // Provider가 준비된 후에 컨트롤러 초기값 설정
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final scene = context.read<VttSocketService>().scene;
        if (scene != null) {
          _updateControllerFromScene(scene);
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 씬이 변경될 때마다(예: 'joinedMap' 이벤트 수신) 컨트롤러 상태 업데이트
    final scene = context.watch<VttSocketService>().scene;
    if (scene != null) {
      _updateControllerFromScene(scene);
    }
  }

  /// VttScene 객체에서 값을 읽어 TransformationController를 설정
  /// 맵의 현재 스케일, X/Y 오프셋을 반영
  void _updateControllerFromScene(VttScene scene) {
    // [신규] VttScene의 imageScale, imageX, imageY 값을 Matrix4로 변환
    _transformationController.value = Matrix4.identity()
      ..translate(scene.imageX, scene.imageY) // Y 오프셋
      ..scale(scene.imageScale); // 스케일
  }

  /// [신규] GM이 맵(배경)을 이동/확대/축소한 후 호출됨
  void _onInteractionEnd(ScaleEndDetails details, VttSocketService vttSocket) {
    // 현재 뷰의 변환(Matrix4) 값을 가져옴
    final matrix = _transformationController.value;

    // Matrix4에서 스케일과 X/Y 오프셋 추출
    final double newScale = matrix.row0[0]; // 스케일
    final double newX = matrix.getTranslation().x;
    final double newY = matrix.getTranslation().y;

    final currentScene = vttSocket.scene;
    if (currentScene == null) return;

    // 현재 씬을 복사하여 새 값으로 갱신
    // (VttScene 모델에 copyWith 메서드가 있다고 가정. 없다면 수동으로 객체 생성)
    // VttScene 모델에 copyWith가 없다면, vtt_scene.dart에 아래와 같이 추가
    /*
      VttScene copyWith({ ... double? imageScale, double? imageX, double? imageY, ... }) {
        return VttScene(
          id: id,
          roomId: roomId,
          name: name,
          ...
          imageScale: imageScale ?? this.imageScale,
          imageX: imageX ?? this.imageX,
          imageY: imageY ?? this.imageY,
          ...
        );
      }
    */
    
    // [신규] VttSocketService의 sendMapUpdate 호출
    // (이전 단계에서 수정한 vtt_socket_service.dart의 새 메서드)
    // vttSocket.sendMapUpdate(currentScene.copyWith(
    //   imageScale: newScale,
    //   imageX: newX,
    //   imageY: newY,
    // ));

    // copyWith가 없다면 수동 생성 (VttScene 모델이 vtt_scene.dart에서 수정한 것과 같다고 가정)
    final updatedScene = VttScene(
      id: currentScene.id,
      roomId: currentScene.roomId,
      name: currentScene.name,
      backgroundUrl: currentScene.backgroundUrl,
      gridType: currentScene.gridType,
      gridSize: currentScene.gridSize,
      showGrid: currentScene.showGrid,
      imageScale: newScale, // 새 값
      imageX: newX,         // 새 값
      imageY: newY,         // 새 값
      localHeight: currentScene.localHeight,
      localWidth: currentScene.localWidth,
      isActive: currentScene.isActive,
      properties: currentScene.properties,
    );
    vttSocket.sendMapUpdate(updatedScene);

    debugPrint('Interaction End: Scale=$newScale, X=$newX, Y=$newY');
  }

  @override
  Widget build(BuildContext context) {
    final vttSocket = Provider.of<VttSocketService>(context);
    final scene = vttSocket.scene;
    final tokens = vttSocket.tokens.values.toList();

    if (scene == null) {
      return const Center(child: Text('씬 정보를 기다리는 중...'));
    }
    if (!vttSocket.isConnected) {
      return const Center(child: Text('VTT 서버에 연결 중...'));
    }

    // [수정됨] 캔버스 전체를 InteractiveViewer로 감싸기
    return InteractiveViewer(
      transformationController: _transformationController,
      // [신규] GM의 맵 조작이 끝났을 때 서버에 업데이트
      onInteractionEnd: (details) => _onInteractionEnd(details, vttSocket),
      minScale: 0.1, // 최소 축소
      maxScale: 10.0, // 최대 확대
      constrained: false, // 캔버스 크기(SizedBox)를 벗어나서 이동/확대 가능
      child: SizedBox(
        // [신규] 캔버스의 "월드" 크기를 VttScene의 로컬 값으로 정의
        width: scene.localWidth.toDouble(),
        height: scene.localHeight.toDouble(),
        child: Stack(
          clipBehavior: Clip.none, // 토큰이 캔버스 밖으로 나가도 보이게 함
          children: [
            // [신규] Layer 1: 배경 이미지 (Transform 적용)
            // InteractiveViewer가 (0,0)을 기준으로 변환하므로
            // 배경 이미지는 (0,0)에 위치시킵니다.
            Positioned(
              left: 0,
              top: 0,
              width: scene.localWidth.toDouble(),
              height: scene.localHeight.toDouble(),
              child: _buildBackgroundImage(scene),
            ),

            // [신규] Layer 2: 그리드 (CustomPainter)
            Positioned.fill(
              child: CustomPaint(
                painter: _GridPainter(
                  showGrid: scene.showGrid,
                  gridSize: scene.gridSize.toDouble(),
                  // VttScene 모델의 properties에서 그리드 색상/투명도 가져오기 (예시)
                  gridColor: Color(
                      int.tryParse(scene.properties['gridColor'] ?? '0xFF000000') ??
                          0xFF000000),
                  gridOpacity:
                      (scene.properties['gridOpacity'] as num?)?.toDouble() ??
                          0.5,
                ),
              ),
            ),

            // [수정됨] Layer 3: 토큰 목록 렌더링
            // 토큰들은 InteractiveViewer의 자식으로 Stack에 포함되어야
            // 맵과 함께 이동/확대/축소 됩니다.
            ...tokens.map(
              (token) => _TokenItem(
                key: ValueKey(token.id),
                token: token,
                // [신규] 토큰 이동 시 스케일 값을 보정하기 위해 컨트롤러 전달
                transformationController: _transformationController,
                onPositionChanged: (newX, newY) {
                  // [수정됨] REST API 대신 웹소켓 'moveToken' 호출
                  // (vtt_socket_service.dart에서 이 함수가
                  //  즉시 로컬 상태를 업데이트(Optimistic Update)하고
                  //  소켓 이벤트를 emit하도록 수정했다고 가정)
                  vttSocket.moveToken(token.id, newX, newY);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// [신규] 배경 이미지를 렌더링하는 위젯
  Widget _buildBackgroundImage(VttScene scene) {
    if (scene.backgroundUrl == null || scene.backgroundUrl!.isEmpty) {
      return Container(color: Colors.grey[300]); // 기본 배경색
    }
    
    // [수정됨] BoxFit.cover 대신 원본 이미지 크기대로 렌더링
    // (InteractiveViewer가 확대/축소를 제어함)
    return CachedNetworkImage(
      imageUrl: scene.backgroundUrl!,
      // [수정됨] fit: BoxFit.none (원본 크기) 또는 BoxFit.fill (캔버스 크기에 맞춤)
      // VttScene에 width/height가 없으므로 캔버스 크기에 맞추는게 좋음.
      fit: BoxFit.fill, 
      placeholder: (context, url) =>
          const Center(child: CircularProgressIndicator()),
      errorWidget: (context, url, error) =>
          const Center(child: Icon(Icons.error, color: Colors.red)),
    );
  }
}

/// [수정됨] 개별 토큰 위젯
class _TokenItem extends StatelessWidget {
  static const double defaultTokenSize = 50.0; // 토큰 기본 크기

  final Token token;
  // [신규] 현재 맵의 스케일 값을 알기 위해 컨트롤러가 필요
  final TransformationController transformationController;
  final void Function(double newX, double newY) onPositionChanged;

  const _TokenItem({
    super.key,
    required this.token,
    required this.transformationController,
    required this.onPositionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: token.x,
      top: token.y,
      // [수정됨] 토큰 크기는 스케일과 관계없이 항상 일정해야 함 (디자인 결정 필요)
      // 만약 맵과 함께 토큰도 커지게 하려면 (token.scale * defaultTokenSize) 사용
      width: defaultTokenSize, 
      height: defaultTokenSize,
      child: GestureDetector(
        onPanUpdate: (details) {
          // [수정됨] 토큰 이동 로직
          // 1. 현재 맵의 스케일 값을 가져옴
          final double currentScale = transformationController.value.row0[0];
          
          // 2. 화면(Screen)상의 이동(delta)을 캔버스(World)상의 이동으로 변환
          // (스케일이 2배이면, 화면에서 10px 움직여도 캔버스에선 5px만 움직여야 함)
          final double dx = details.delta.dx / currentScale;
          final double dy = details.delta.dy / currentScale;

          // 3. 캔버스상의 새 좌표 계산
          final newX = token.x + dx;
          final newY = token.y + dy;
          
          // 4. 부모 위젯(VttCanvas)에 새 좌표 전달
          onPositionChanged(newX, newY);
        },
        child: Tooltip(
          message: token.name,
          child: Opacity(
            opacity: token.isVisible ? 0.95 : 0.4,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(defaultTokenSize / 2),
                border: Border.all(color: Colors.black45, width: 1.5),
                color: Colors.blueGrey[100],
                image: (token.imageUrl != null && token.imageUrl!.isNotEmpty)
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(token.imageUrl!),
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
              child: (token.imageUrl == null || token.imageUrl!.isEmpty)
                  ? Center(
                      child: Text(
                        token.name.isNotEmpty ? token.name[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: defaultTokenSize * 0.6,
                          color: Colors.black87,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

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
    // 씬 정보가 변경될 때만 다시 그림
    return oldDelegate.showGrid != showGrid ||
        oldDelegate.gridSize != gridSize ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.gridOpacity != gridOpacity;
  }
}
