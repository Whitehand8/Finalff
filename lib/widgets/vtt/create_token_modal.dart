import 'dart:typed_data'; // [신규] Uint8List 사용
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // [신규] image_picker import
import 'package:provider/provider.dart';
import 'package:trpg_frontend/services/ApiClient.dart'; // [신규] ApiClient import
import 'package:trpg_frontend/services/token_service.dart';
import 'package:trpg_frontend/services/vtt_socket_service.dart';

/// 캔버스에 새 이미지 토큰을 생성하기 위한 모달 위젯입니다.
class CreateTokenModal extends StatefulWidget {
  const CreateTokenModal({super.key});

  @override
  State<CreateTokenModal> createState() => _CreateTokenModalState();
}

class _CreateTokenModalState extends State<CreateTokenModal> {
  // final TextEditingController _urlController = TextEditingController(); // [수정] URL 컨트롤러 제거
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = false;
  String _loadingStatus = ''; // [신규] 로딩 상태 메시지

  // [신규] 선택된 파일을 관리하기 위한 변수
  XFile? _pickedFile;
  Uint8List? _fileBytes;

  /// [신규] 이미지 선택 버튼을 눌렀을 때 실행되는 함수
  Future<void> _pickImage() async {
    if (_isLoading) return;
    final ImagePicker picker = ImagePicker();
    try {
      // 갤러리에서 이미지 선택 (웹/모바일 호환)
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _pickedFile = image;
          _fileBytes = bytes;
        });
      }
    } catch (e) {
      _showError('이미지를 선택하는 중 오류가 발생했습니다: $e');
    }
  }

  /// [수정] "확인" 버튼을 눌렀을 때 S3 업로드 및 토큰 생성을 요청하는 함수
  Future<void> _handleCreateToken() async {
    if (!mounted) return;

    final vttSocket = context.read<VttSocketService>();
    final tokenService = TokenService.instance;
    final apiClient = ApiClient.instance; // [신규] ApiClient 인스턴스 사용
    

    final String? mapId = vttSocket.scene?.id;
    if (mapId == null) {
      _showError('현재 입장한 맵이 없습니다. 맵에 먼저 입장해주세요.');
      return;
    }

    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('토큰 이름을 입력해주세요.');
      return;
    }

    // [수정] URL 대신 파일이 선택되었는지 확인
    if (_pickedFile == null || _fileBytes == null) {
      _showError('이미지 파일을 선택해주세요.');
      return;
    }

    final String fileName = _pickedFile!.name;
    // 파일 확장자로부터 MIME 타입 추정 (더 안정적)
    final String fileExtension = fileName.split('.').last.toLowerCase();
    
    final String fileType;
    if (fileExtension == 'png') {
      fileType = 'image/png';
    } else if (fileExtension == 'jpg' || fileExtension == 'jpeg') {
      fileType = 'image/jpeg';
    } else if (fileExtension == 'webp') {
      fileType = 'image/webp';
    } else {
      // 🚨 백엔드가 허용하지 않는 다른 모든 확장자
      _showError('허용되지 않는 파일 형식입니다. (png, jpg, jpeg, webp)');
      setState(() => _isLoading = false);
      return; // 👈 API 호출 전에 함수를 종료
    } // 기본값

    if (fileType == 'image/octet-stream') {
       debugPrint('경고: 알 수 없는 파일 확장자($fileExtension). 기본 MIME 타입 사용.');
    }

    setState(() {
      _isLoading = true;
      _loadingStatus = 'Presigned URL 요청 중...';
    });

    try {
      // 1. 백엔드에 Presigned URL 요청
      final s3Urls = await apiClient.getPresignedUrl(fileName, fileType);
      final String presignedUrl = s3Urls['presignedUrl']!;
      final String finalFileUrl = s3Urls['fileUrl']!; // DB에 저장될 최종 URL

      if (!mounted) return;
      setState(() => _loadingStatus = 'S3에 업로드 중...');

      // 2. S3로 파일 업로드 (ApiClient에 추가한 함수 사용)
      await apiClient.uploadFileToS3(presignedUrl, _fileBytes!, fileType);

      if (!mounted) return;
      setState(() => _loadingStatus = '토큰 생성 중...');

      // 3. S3 업로드 성공 후, 최종 URL로 토큰 생성
      await tokenService.createToken(
        mapId: mapId,
        name: name,
        imageUrl: finalFileUrl, // [수정] S3 URL 사용
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // 성공 시 모달 닫기
      
    } on TokenServiceException catch (e) {
      _showError('토큰 생성 실패: ${e.message}');
    } catch (e) {
      _showError('알 수 없는 오류가 발생했습니다: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingStatus = '';
        });
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  void dispose() {
    // _urlController.dispose(); // [수정] 제거
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('새 이미지 토큰 생성'),
      content: SingleChildScrollView( // [신규] 스크롤 추가
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '토큰 이름',
                hintText: '예: 나무, 보물상자',
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 24),
            
            // [신규] URL 입력창 대신 파일 선택 UI
            Container(
              height: 150,
              width: double.maxFinite,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey.shade50,
              ),
              child: InkWell(
                onTap: _isLoading ? null : _pickImage, // 로딩 중 클릭 방지
                child: _fileBytes == null
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined, size: 40, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('이미지 선택하기'),
                          ],
                        ),
                      )
                    : Padding( // [신규] 이미지 미리보기
                        padding: const EdgeInsets.all(8.0),
                        child: Image.memory(
                          _fileBytes!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => 
                            const Center(child: Text('미리보기 실패')),
                        ),
                      ),
              ),
            ),
            
            if (_pickedFile != null) // [신규] 선택된 파일 이름 표시
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  _pickedFile!.name,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            if (_isLoading) // [신규] 로딩 상태 표시
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16, 
                      height: 16, 
                      child: CircularProgressIndicator(strokeWidth: 2)
                    ),
                    const SizedBox(width: 12),
                    Text(_loadingStatus),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        ElevatedButton(
          // [수정] 로딩 중이거나 파일이 없으면 비활성화
          onPressed: (_isLoading || _pickedFile == null) ? null : _handleCreateToken,
          child: const Text('생성'),
        ),
      ],
    );
  }
}