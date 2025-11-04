// lib/widgets/vtt/map_list_item_widget.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:trpg_frontend/models/vtt_scene.dart';
import 'package:trpg_frontend/services/vtt_socket_service.dart';

class MapListItemWidget extends StatelessWidget {
  final VttScene map;
  final bool isGm;

  const MapListItemWidget({
    super.key,
    required this.map,
    required this.isGm,
  });

  /// '입장' 버튼을 눌렀을 때 실행되는 함수
  void _joinMap(BuildContext context) {
    if (map.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('유효하지 않은 맵 ID입니다.')),
      );
      return;
    }

    try {
      // VttSocketService의 connectAndJoin을 호출하여 맵에 접속
      context.read<VttSocketService>().connectAndJoin(map.id!);
      
      // 성공적으로 join을 요청한 후 모달을 닫음
      Navigator.of(context).pop(); 
    } catch (e) {
      // Provider를 찾지 못하는 등의 예외 처리
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('맵 입장에 실패했습니다: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      child: ListTile(
        // --- 1. 맵 썸네일 ---
        leading: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.grey[800], // 기본 배경색
            borderRadius: BorderRadius.circular(4),
          ),
          // 맵 배경 이미지 URL이 있으면 CachedNetworkImage로 표시
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
              : const Icon(Icons.map, color: Colors.grey), // 이미지가 없으면 기본 아이콘
        ),

        // --- 2. 맵 이름 ---
        title: Text(
          map.name.isNotEmpty ? map.name : '(이름 없는 맵)',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'ID: ${map.id}', // (선택) 디버깅용 ID 표시
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),

        // --- 3. 입장 버튼 ---
        trailing: ElevatedButton(
          onPressed: () => _joinMap(context),
          child: const Text('입장'),
        ),
        
        // TODO: (선택) GM인 경우 맵 설정/삭제 버튼 추가
        // onTap: isGm ? () => _showMapSettingsModal(context, map) : null,
      ),
    );
  }
}