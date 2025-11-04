// lib/widgets/vtt/map_select_modal.dart
import 'package:flutter/material.dart';
import 'package:trpg_frontend/models/vtt_scene.dart';
import 'package:trpg_frontend/services/vtt_service.dart';
// ⚠️ 이 파일(map_list_item_widget.dart)은 다음 단계에서 생성할 예정입니다.
import 'package:trpg_frontend/widgets/vtt/map_list_item_widget.dart';

class MapSelectModal extends StatefulWidget {
  final String roomId;
  final bool isGm;

  const MapSelectModal({
    super.key,
    required this.roomId,
    required this.isGm,
  });

  @override
  State<MapSelectModal> createState() => _MapSelectModalState();
}

class _MapSelectModalState extends State<MapSelectModal> {
  // VttService (REST API)를 사용하여 맵 목록을 비동기적으로 불러옵니다.
  late final Future<List<VttScene>> _mapsFuture;

  @override
  void initState() {
    super.initState();
    _mapsFuture = VttService.instance.getVttMapsByRoom(widget.roomId);
  }

  // TODO: 새 맵 생성 모달을 띄우는 로직 (GM 전용)
  void _showCreateMapModal() {
    // 이 부분은 추후 맵 생성 UI가 준비되면 구현합니다.
    Navigator.of(context).pop(); // 일단 모달 닫기
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('맵 생성 기능은 아직 구현되지 않았습니다.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('맵 선택'),
      // 내용이 길어질 수 있으므로 SizedBox로 높이 제한
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6, // 화면 높이의 60%
        child: FutureBuilder<List<VttScene>>(
          future: _mapsFuture,
          builder: (context, snapshot) {
            // 1. 로딩 중
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            // 2. 에러 발생
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  '맵 목록을 불러오는 데 실패했습니다:\n${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                ),
              );
            }

            // 3. 데이터 없음 (성공했으나 리스트가 비어있음)
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    '이 방에 생성된 맵이 없습니다.\n(GM이 "새 맵 생성" 버튼으로 맵을 만들어야 합니다)',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            // 4. 데이터 로드 성공
            final maps = snapshot.data!;
            return ListView.builder(
              shrinkWrap: true,
              itemCount: maps.length,
              itemBuilder: (context, index) {
                final map = maps[index];
                // (다음 단계에서 생성할) 개별 맵 항목 위젯
                return MapListItemWidget(
                  map: map,
                  isGm: widget.isGm,
                );
              },
            );
          },
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        // GM인 경우 '새 맵 생성' 버튼 표시
        if (widget.isGm)
          ElevatedButton.icon(
            onPressed: _showCreateMapModal,
            icon: const Icon(Icons.add),
            label: const Text('새 맵 생성'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
            ),
          ),
        
        // 닫기 버튼
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}