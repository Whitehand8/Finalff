// lib/widgets/vtt/map_list_item_widget.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:trpg_frontend/models/vtt_scene.dart';
import 'package:trpg_frontend/services/vtt_socket_service.dart';
// [신규] VttService import (맵 삭제용)
import 'package:trpg_frontend/services/vtt_service.dart';

class MapListItemWidget extends StatelessWidget {
  final VttScene map;
  final bool isGm;
  // [신규] 맵 삭제/생성 후 목록 새로고침을 위한 콜백
  final VoidCallback? onMapChanged;

  const MapListItemWidget({
    super.key,
    required this.map,
    required this.isGm,
    this.onMapChanged, // [신규]
  });

  /// '입장' 버튼을 눌렀을 때 실행되는 함수
  void _joinMap(BuildContext context) {
    // --- 🚨 [수정됨] ---
    // 'map.id == null' 대신 'map.id.isEmpty'로 검사
    if (map.id.isEmpty) { 
    // --- 🚨 [수정 끝] ---
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('유효하지 않은 맵 ID입니다.')),
      );
      return;
    }

    try {
      // --- 🚨 [수정됨] ---
      // VttSocketService의 joinMap 메서드를 호출 ('!' 제거)
      context.read<VttSocketService>().joinMap(map.id);
      // --- 🚨 [수정 끝] ---
      
      // 성공적으로 join을 요청한 후 모달을 닫음
      Navigator.of(context).pop(); 
    } catch (e) {
      // Provider를 찾지 못하는 등의 예외 처리
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('맵 입장에 실패했습니다: $e')),
      );
    }
  }

  /// [신규] 맵 삭제 로직
  void _deleteMap(BuildContext context) {
    // 확인 다이얼로그 표시
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('맵 삭제 확인'),
        content: Text("'${map.name}' 맵을 정말 삭제하시겠습니까?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              try {
                // 1. vtt_service.dart의 deleteMap API 호출
                await VttService.instance.deleteVttMap(map.id);
                
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${map.name} 맵이 삭제되었습니다.')),
                );
                
                // 2. 다이얼로그 닫기
                Navigator.of(dialogContext).pop();
                
                // 3. MapSelectModal의 목록 새로고침
                onMapChanged?.call();

              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('맵 삭제 실패: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      child: ListTile(
        leading: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.grey[800], 
            borderRadius: BorderRadius.circular(4),
          ),
          child: (map.backgroundUrl != null && map.backgroundUrl!.isNotEmpty)
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: map.backgroundUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    errorWidget: (context, url, error) =>
                        const Icon(Icons.image_not_supported, color: Colors.grey),
                  ),
                )
              : const Icon(Icons.map, color: Colors.grey), 
        ),

        title: Text(
          map.name.isNotEmpty ? map.name : '(이름 없는 맵)',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'ID: ${map.id}', 
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),

        // --- 3. 입장 및 관리 버튼 ---
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // GM인 경우 삭제 버튼 표시
            if (isGm)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                tooltip: '맵 삭제',
                onPressed: () => _deleteMap(context), // [신규]
              ),
            // 입장 버튼
            ElevatedButton(
              onPressed: () => _joinMap(context),
              child: const Text('입장'),
            ),
          ],
        ),
      ),
    );
  }
}