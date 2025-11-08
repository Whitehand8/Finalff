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
  // [수정됨] 맵 생성 후 목록을 새로고침하기 위해 Future 변수에서 Key로 변경
  Key _futureBuilderKey = UniqueKey();
  late Future<List<VttScene>> _mapsFuture;

  @override
  void initState() {
    super.initState();
    _loadMaps();
  }
  
  /// 맵 목록을 불러오는 함수
  void _loadMaps() {
     _mapsFuture = VttService.instance.getVttMapsByRoom(widget.roomId);
  }

  /// [수정됨] 맵 목록을 새로고침하는 함수
  void _refreshMapList() {
    setState(() {
      _futureBuilderKey = UniqueKey(); // FutureBuilder를 강제로 재실행
      _loadMaps();
    });
  }

  /// [수정됨] 새 맵 생성을 위한 다이얼로그 표시
  void _showCreateMapModal() {
    final TextEditingController nameController = TextEditingController();
    
    showDialog(
      context: context,
      // 부모 다이얼로그(MapSelectModal)와 겹치지 않도록
      // rootNavigator: true 옵션을 사용 (선택 사항)
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('새 맵 생성'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '맵 이름',
              hintText: '예: 안개 낀 숲',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () async {
                final String name = nameController.text.trim();
                if (name.isEmpty) return; // 이름이 비어있으면 무시

                try {
                  // 1. vtt_service.dart의 createVttMap 함수 호출
                  await VttService.instance.createVttMap(widget.roomId, name);
                  
                  if (!mounted) return;
                  
                  // 2. 생성 성공 시 다이얼로그 닫기
                  Navigator.of(dialogContext).pop();
                  
                  // 3. 맵 목록 새로고침
                  _refreshMapList();

                } catch (e) {
                  // 에러 발생 시 스낵바 표시
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('맵 생성 실패: $e'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                }
              },
              child: const Text('생성'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('맵 선택'),
          // 맵 목록 새로고침 버튼
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: _refreshMapList,
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6, 
        child: FutureBuilder<List<VttScene>>(
          key: _futureBuilderKey, // [수정됨] 새로고침을 위한 Key
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
            onPressed: _showCreateMapModal, // [수정됨] 실제 로직 연결
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