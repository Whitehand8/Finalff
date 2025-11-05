import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart'; // Provider import
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trpg_frontend/models/room.dart';
import 'package:trpg_frontend/models/participant.dart'; // 수정된 Participant 모델 import
import 'package:trpg_frontend/router/routers.dart';
import 'package:trpg_frontend/services/room_service.dart';
import 'package:trpg_frontend/services/auth_service.dart'; // AuthService for user ID

// --- ✨ NPC 관련 Import ---
import 'package:trpg_frontend/models/npc.dart';
import 'package:trpg_frontend/providers/npc_provider.dart'; // NpcProvider import
import 'package:trpg_frontend/widgets/npc/npc_list_item.dart'; // NPC 목록 아이템 위젯
import 'package:trpg_frontend/widgets/npc/npc_create_modal.dart'; // NPC 생성 모달
import 'package:trpg_frontend/widgets/npc/npc_detail_modal.dart'; // NPC 상세/수정 모달
// --- ✨ ---

// --- ✅ 1. Chat 관련 Import (기존과 동일) ---
import 'package:trpg_frontend/services/chat_service.dart';
import 'package:trpg_frontend/widgets/chat/chat_list_widget.dart';
// --- ✅ ---

// --- ✅ 2. VTT 관련 Import (기존과 동일) ---
import 'package:trpg_frontend/services/vtt_socket_service.dart';
import 'package:trpg_frontend/features/vtt/vtt_canvas.dart';
import 'package:trpg_frontend/widgets/vtt/map_select_modal.dart';
// --- ✅ ---

// --- ✅ 3. Dice 관련 Import 추가 ---
import 'package:trpg_frontend/widgets/dice/dice_roll_modal.dart';
// --- ✅ ---

class RoomScreen extends StatefulWidget {
  final Room room;
  const RoomScreen({super.key, required this.room});

  // --- Provider 제공 (기존과 동일) ---
  static Widget create({required Room room}) {
    if (room.id == null) {
      return const Scaffold(
        body: Center(child: Text('유효한 방 ID가 없습니다.')),
      );
    }
    
    // chatRoomId null 체크
    if (room.chatRoomId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('오류')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              '채팅방 ID를 불러오지 못했습니다.\n방을 다시 만들거나 참여해주세요.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    // NpcProvider와 ChatService를 모두 주입하기 위해 MultiProvider 사용
    return MultiProvider(
      providers: [
        // 기존 NpcProvider (TRPG Room의 String ID 사용)
        ChangeNotifierProvider(
          create: (_) => NpcProvider(room.id!), // 생성 시 roomId 전달 및 NPC 로딩 시작
        ),
        // 새로 추가된 ChatService Provider
        ChangeNotifierProvider(
          create: (_) => ChatService(room.chatRoomId!), // 채팅방의 숫자 ID 전달
        ),
        // VttSocketService 주입 (TRPG Room의 String ID 사용)
        ChangeNotifierProvider(
      create: (_) => VttSocketService(
        // 1. 이름 없는 위치 인수(positional argument)를 삭제합니다.
        // room.id!, // <-- 🚨 이 줄을 삭제하세요.

        // 2. 이름이 지정된 'roomId' 인수는 그대로 둡니다. (필수)
        roomId: room.id!, 
        
        // 3. 'onRoomEvent' 인수도 그대로 둡니다. (필수)
        onRoomEvent: (eventName, data) {
          debugPrint('[VTT Room Event] $eventName: $data');
        },
      ),
    ),
      ],
      child: RoomScreen(room: room),
    );
  }
  // --- ---

  // byId 생성자 (기존과 동일)
  static Widget byId({required String roomId}) {
    return FutureBuilder<Room>(
      future: RoomService.getRoom(roomId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('오류')),
            body: Center(child: Text('방을 불러올 수 없습니다: ${snapshot.error}')),
          );
        }
        // ✨ RoomScreen.create 메서드를 사용하여 Provider와 함께 생성
        return RoomScreen.create(room: snapshot.data!);
      },
    );
  }

  @override
  RoomScreenState createState() => RoomScreenState();
}

class RoomScreenState extends State<RoomScreen> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _chatController = TextEditingController();
  late Room _room;
  List<Participant> _participants = [];
  bool _isParticipantsLoading = false;

  // --- ✨ GM 플래그 및 사용자 ID 추가 ---
  bool _isCurrentUserGm = false;
  int? _currentUserId; // 현재 로그인된 사용자의 ID (from AuthService, int)
  // --- ✨ ---

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _room = widget.room;
    _initializeScreen(); // ✨ 초기화 로직 통합
  }

  // --- ✨ 초기화 함수 (기존과 동일) ---
  Future<void> _initializeScreen() async {
    await _loadCurrentUserId(); // AuthService에서 사용자 ID 가져오기
    await _loadParticipants(); // 참여자 목록 로드 (내부에서 _checkCurrentUserRole 호출)
  }
  // --- ✨ ---

  // --- ✨ 현재 사용자 ID 로드 함수 (기존과 동일) ---
  Future<void> _loadCurrentUserId() async {
    final userId = await AuthService.instance.getCurrentUserId();
    if (mounted) {
      setState(() {
        _currentUserId = userId; // 상태 변수에 저장
      });
    }
  }
  // --- ✨ ---

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chatController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _validateRoomStillExists();
      context.read<NpcProvider>().fetchNpcs();
      _loadParticipants(); 
    }
  }

  // 방 유효성 검사 (기존과 동일)
  Future<void> _validateRoomStillExists() async {
    final roomId = _room.id;
    if (roomId == null) return;
    try {
      await RoomService.getRoom(roomId);
    } on RoomServiceException catch (e) {
      if (e.statusCode == 404 && mounted) {
        _showError('방이 삭제되어 더 이상 접근할 수 없습니다.');
        context.go(Routes.rooms); // 방 목록 화면으로 이동
      }
    }
  }

  // 참여자 목록 로드 및 역할 확인 (기존과 동일)
  Future<void> _loadParticipants() async {
    if (_room.id == null) return;
    if (!mounted) return;
    setState(() => _isParticipantsLoading = true);
    try {
      final participants = await RoomService.getParticipants(_room.id!);
      if (mounted) {
        setState(() => _participants = participants);
        _checkCurrentUserRole(); // ✨ 참여자 로드 후 역할 확인
      }
    } catch (e) {
      if (mounted) _showError('참여자 목록 로딩 실패: $e');
    } finally {
      if (mounted) setState(() => _isParticipantsLoading = false);
    }
  }

  // --- ✨ 현재 사용자 역할 확인 로직 (기존과 동일) ---
  void _checkCurrentUserRole() {
    if (_currentUserId != null && _participants.isNotEmpty) {
      final currentUserParticipant = _participants.firstWhere(
        (p) => p.id == _currentUserId,
        orElse: () => Participant(id: 0, nickname: '', name: '', role: 'PLAYER'),
      );
      final isGm = currentUserParticipant.role == 'GM';
      if (mounted && _isCurrentUserGm != isGm) {
        setState(() {
          _isCurrentUserGm = isGm;
        });
      }
    } else if (mounted && _isCurrentUserGm != false) {
      setState(() {
        _isCurrentUserGm = false;
      });
    }
  }
  // --- ✨ ---

  // --- ✅ 방 관리 함수들 (축약 해제) ---
  Future<void> _leaveRoom() async {
    // 방장인지 확인
    if (_room.creatorId == _currentUserId) {
      _showCannotLeaveAsCreatorDialog();
      return;
    }
    // 일반 참여자
    _showLeaveRoomDialog();
  }

  void _showCannotLeaveAsCreatorDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('방 나가기 실패'),
        content: const Text('방장은 방을 나갈 수 없습니다. 방을 삭제하거나 다른 사람에게 방장을 위임하세요.'),
        actions: [
          TextButton(onPressed: Navigator.of(context).pop, child: const Text('확인')),
        ],
      ),
    );
  }

  void _showLeaveRoomDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('방 나가기'),
        content: const Text('정말로 이 방을 나가시겠습니까?'),
        actions: [
          TextButton(onPressed: Navigator.of(context).pop, child: const Text('취소')),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop(); // 다이얼로그 닫기
              try {
                await RoomService.leaveRoom(_room.id!);
                if (!mounted) return;
                _showSuccess('방에서 나갔습니다.');
                context.go(Routes.rooms); // 방 목록으로 이동
              } on RoomServiceException catch (e) {
                if(mounted) _showError('방 나가기 실패: ${e.message}');
              }
            },
            child: const Text('나가기', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRoom() async {
    if (_room.creatorId != _currentUserId) {
      _showError('방 삭제는 방장만 가능합니다.');
      return;
    }
    _showDeleteRoomDialog();
  }

  void _showDeleteRoomDialog() {
     showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('방 삭제'),
        content: const Text('정말로 이 방을 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.'),
        actions: [
          TextButton(onPressed: Navigator.of(context).pop, child: const Text('취소')),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop(); // 다이얼로그 닫기
              try {
                await RoomService.deleteRoom(_room.id!);
                if (!mounted) return;
                _showSuccess('방이 삭제되었습니다.');
                context.go(Routes.rooms); // 방 목록으로 이동
              } on RoomServiceException catch (e) {
                if(mounted) _showError('방 삭제 실패: ${e.message}');
              }
            },
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _transferCreator(int newCreatorId) async {
     try {
       await RoomService.transferCreator(_room.id!, newCreatorId);
       if (!mounted) return;
       _showSuccess('방장이 위임되었습니다.');
       // 방 정보(creatorId)가 변경되었으므로 새로고침
       _validateRoomStillExists(); 
       _loadParticipants();
     } on RoomServiceException catch (e) {
       if (!mounted) return;
       _showError('방장 위임 실패: ${e.message}');
     }
  }

  void _showTransferCreatorDialog() {
    if (_room.creatorId != _currentUserId) {
       _showError('방장 위임은 현재 방장만 가능합니다.');
       return;
    }
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('방장 위임'),
        content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '새 방장의 Participant ID')),
        actions: [
          TextButton(onPressed: Navigator.of(context).pop, child: const Text('취소')),
          ElevatedButton(
            onPressed: () {
              final id = int.tryParse(controller.text.trim());
              if (id == null) {
                 _showError('유효한 ID를 입력해주세요.');
                 return;
              }
              Navigator.of(context).pop();
              _transferCreator(id);
            },
            child: const Text('위임'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateParticipantRole(int participantId, String newRole) async {
    try {
      await RoomService.updateParticipantRole(_room.id!,
          participantId.toString(), newRole); // API가 String ID를 받을 경우 .toString()
      if (!mounted) return;
      _showSuccess('역할이 변경되었습니다.');
      _loadParticipants(); // 목록 새로고침
    } on RoomServiceException catch (e) {
      if (!mounted) return;
      _showError('역할 변경 실패: ${e.message}');
    }
  }

  void _showUpdateRoleDialog() {
    if (_room.creatorId != _currentUserId) {
      _showError('역할 변경은 방장만 가능합니다.');
      return;
    }
    final participantIdController = TextEditingController(); // Participant ID 입력용
    final roleController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('참여자 역할 변경'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField( // Participant ID 입력 필드
                controller: participantIdController,
                keyboardType: TextInputType.number, // 숫자 입력
                decoration:
                    const InputDecoration(labelText: 'Participant ID')), // 레이블 변경
            TextField( // 역할 입력 필드
                controller: roleController,
                decoration:
                    const InputDecoration(labelText: '새 역할 (GM/PLAYER)')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: Navigator.of(context).pop, child: const Text('취소')),
          ElevatedButton(
            onPressed: () {
              final idText = participantIdController.text.trim();
              final roleText =
                  roleController.text.trim().toUpperCase(); // 역할은 대문자로
              final participantId = int.tryParse(idText); // int로 변환 시도

              if (participantId == null) {
                // 유효한 숫자인지 확인
                _showError('유효한 Participant ID를 입력해주세요.');
                return;
              }
              if (roleText != 'GM' && roleText != 'PLAYER') {
                // 역할 유효성 검사
                _showError('역할은 GM 또는 PLAYER 여야 합니다.');
                return;
              }
              Navigator.of(context).pop(); // 다이얼로그 닫기
              _updateParticipantRole(participantId, roleText); // 업데이트 함수 호출
            },
            child: const Text('변경'),
          ),
        ],
      ),
    );
  }
  // --- ---

  // --- ✅ NPC 관련 UI 호출 함수 (축약 해제) ---
  void _showNpcListModal() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        // Consumer를 사용하여 NpcProvider의 상태 변화를 실시간으로 반영
        return Consumer<NpcProvider>(
          builder: (context, npcProvider, child) {
            final npcs = npcProvider.npcs;
            final isLoading = npcProvider.isLoading;
            final error = npcProvider.error;
            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('NPC 목록'),
                  isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: '새로고침',
                          // read를 사용하여 NpcProvider의 함수 호출
                          onPressed: () =>
                              context.read<NpcProvider>().fetchNpcs()),
                ],
              ),
              content: SizedBox(
                 width: double.maxFinite,
                 child: error != null
                    ? Center(
                        child: Text('오류: $error',
                            style: const TextStyle(color: Colors.red)))
                    : npcs.isEmpty && !isLoading
                        ? const Center(child: Text('등록된 NPC가 없습니다.'))
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: npcs.length,
                            itemBuilder: (context, index) {
                              final npc = npcs[index];
                              return NpcListItem(
                                npc: npc,
                                onTap: () {
                                  Navigator.pop(dialogContext); // 목록 모달 닫기
                                  _showNpcDetailModal(npc);   // 상세 모달 열기
                                },
                              );
                            },
                          ),
              ),
              actions: [
                TextButton(
                    onPressed: Navigator.of(dialogContext).pop,
                    child: const Text('닫기')),
              ],
            );
          },
        );
      },
    );
  }

  void _showNpcDetailModal(Npc npc) {
    showDialog(
      context: context,
      // NpcDetailModal이 NpcProvider를 사용할 수 있도록
      // Provider를 한 단계 더 주입 (ChangeNotifierProvider.value 사용)
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<NpcProvider>(), // 기존 Provider 인스턴스 전달
        child: NpcDetailModal(npc: npc, isGm: _isCurrentUserGm),
      ),
    );
  }

  void _showCreateNpcModal() {
    if (!_isCurrentUserGm) {
      _showError('NPC 생성은 GM만 가능합니다.');
      return;
    }
    showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<NpcProvider>(), // NpcCreateModal도 Provider가 필요
        child: NpcCreateModal(roomId: _room.id!),
      ),
    );
  }
  // --- ✨ ---

  // --- VTT 맵 선택 모달 (기존과 동일) ---
  void _showMapSelectModal() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return MapSelectModal(
          roomId: _room.id!, // TRPG 룸 ID (String) 전달
          isGm: _isCurrentUserGm,
        );
      },
    );
  }
  // --- ✅ ---

  // --- ✅ 주사위 굴림 모달 호출 함수 (신규) ---
  void _showDiceRollModal() {
    // 1. 현재 사용자 닉네임 찾기
    String nickname = '참여자'; // 기본값
    if (_currentUserId != null) {
      final me = _participants.firstWhere(
        (p) => p.id == _currentUserId,
        orElse: () => Participant(id: 0, nickname: '알 수 없음', name: '', role: 'PLAYER'),
      );
      nickname = me.nickname;
    }

    // 2. 모달 띄우기
    showDialog(
      context: context,
      builder: (dialogContext) {
        // ChatService는 Provider를 통해 주입되므로 모달이 context.read로 접근 가능
        return DiceRollModal(rollerNickname: nickname);
      },
    );
  }
  // --- ✅ ---


  // === UI 빌드 ===
  @override
  Widget build(BuildContext context) {
    // ✨ NpcProvider 에러 상태 감시 (기존과 동일)
    final npcError = context.select((NpcProvider p) => p.error);
    if (npcError != null && ModalRoute.of(context)?.isCurrent == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showError('NPC 오류: $npcError');
        context.read<NpcProvider>().clearError(); // 에러 메시지 클리어
      });
    }

    return Scaffold(
      key: _scaffoldKey,
      // --- ✅ AppBar 수정 (주사위 버튼 onPressed 연결) ---
      appBar: AppBar(
        title: Text(_room.name),
        backgroundColor: const Color(0xFF8C7853), // 테마 색상 적용
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(), // 뒤로가기
        ),
        actions: [
          // 주사위 버튼 (onPressed 수정)
          IconButton(
            icon: const Icon(Icons.casino),
            tooltip: '주사위 굴리기',
            onPressed: _showDiceRollModal, // ✅ 로직 연결
          ),
          
          // --- 맵 선택 버튼 (기존과 동일) ---
          IconButton(
            icon: const Icon(Icons.map_outlined), // 맵 아이콘
            tooltip: '맵 선택/로드',
            onPressed: _showMapSelectModal, // 맵 선택 모달 호출
          ),

          // ✨ NPC 목록 버튼 (기존과 동일)
          IconButton(
            icon: const Icon(Icons.book_outlined), // 아이콘 변경
            tooltip: 'NPC 목록',
            onPressed: _showNpcListModal, // NPC 목록 모달 호출
          ),
          // 참여자 목록 버튼 (기존과 동일)
          IconButton(
            icon: const Icon(Icons.people),
            tooltip: '참여자 목록',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
          // --- 방 관리 메뉴 (기존과 동일) ---
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'leave':
                  _showLeaveRoomDialog();
                  break;
                case 'delete':
                  _showDeleteRoomDialog();
                  break;
                case 'transfer':
                  _showTransferCreatorDialog();
                  break;
                case 'updateRole':
                  _showUpdateRoleDialog();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'leave',
                child:
                    ListTile(leading: Icon(Icons.exit_to_app), title: Text('방 나가기')),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(
                    leading: Icon(Icons.delete_forever, color: Colors.red),
                    title: Text('방 삭제', style: TextStyle(color: Colors.red))),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'transfer',
                child: ListTile(
                    leading: Icon(Icons.person_pin_circle_outlined),
                    title: Text('방장 위임')),
              ),
              const PopupMenuItem<String>(
                value: 'updateRole',
                child: ListTile(
                    leading: Icon(Icons.admin_panel_settings_outlined),
                    title: Text('참여자 역할 변경')),
              ),
            ],
          ),
          // --- ✨ ---
        ],
      ),
      // --- ✅ Body (기존과 동일) ---
      body: Consumer<NpcProvider>(
          builder: (context, npcProvider, child) {
        if (npcProvider.isLoading && npcProvider.npcs.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return Stack(
          children: [
            // VTT Canvas
            const Positioned.fill(child: VttCanvas()), 
            // 채팅 UI
            ChatListWidget(
              participants: _participants,
              currentUserId: _currentUserId,
            ),
          ],
        );
      }),
      // --- ✅ ---
      // --- ✅ 참여자 Drawer (축약 해제) ---
      endDrawer: Drawer(
        child: Column(
          children: [
            AppBar(
                title: const Text('참여자'), automaticallyImplyLeading: false, 
                backgroundColor: const Color(0xFF8C7853)
            ),
            ListTile(
              title: const Text('참여자 목록'),
              trailing: _isParticipantsLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: '새로고침',
                      onPressed: _loadParticipants),
            ),
            Expanded(
              // 참여자 리스트
              child: _participants.isEmpty
                  ? const Center(child: Text('참여자가 없습니다.'))
                  : ListView.builder(
                      itemCount: _participants.length,
                      itemBuilder: (context, index) {
                        final p = _participants[index];
                        // ✨ 방장 ID와 Participant ID 비교 (Room.creatorId 타입 확인 필요)
                        final bool isCreator =
                            _room.creatorId != null && p.id == _room.creatorId;
                        return ListTile(
                          // ✨ Participant.nickname 사용
                          leading: CircleAvatar(
                              child: Text(p.nickname.isNotEmpty
                                  ? p.nickname[0].toUpperCase()
                                  : '?')),
                          title: Text(p.nickname),
                          // ✨ Participant.id 표시
                          subtitle: Text('ID: ${p.id} / Role: ${p.role}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 방장/GM 아이콘
                              if (isCreator)
                                const Tooltip(
                                    message: '방장',
                                    child: Icon(Icons.shield_moon_sharp,
                                        color: Colors.blue)),
                              if (p.role == 'GM')
                                const Tooltip(
                                    message: 'GM',
                                    child:
                                        Icon(Icons.star, color: Colors.amber)),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      // --- ✨ ---
      // --- ✨ 하단 바 (기존과 동일) ---
      bottomNavigationBar: _buildBottomBar(),
      // --- ✨ GM 전용 NPC 생성 버튼 (기존과 동일) ---
      floatingActionButton: _isCurrentUserGm
          ? FloatingActionButton(
              onPressed: _showCreateNpcModal, // NPC 생성 모달 호출
              tooltip: 'NPC 생성',
              child: const Icon(Icons.add),
              backgroundColor: Colors.brown[700], // 색상 조정
            )
          : null, // GM 아니면 숨김
      floatingActionButtonLocation:
          FloatingActionButtonLocation.endDocked, // 버튼 위치 조정
      // --- ✨ ---
    );
  }

  // 하단 바 (BottomAppBar + 채팅 입력)
  Widget _buildBottomBar() {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(), // FAB 부분 홈 파기 (선택적)
      notchMargin: 6.0, // 홈 간격 (선택적)
      child: _buildBottomChatBar(),
    );
  }

  // 채팅 입력 바 (키보드 높이 감안)
  Widget _buildBottomChatBar() {
    return Container(
      padding: EdgeInsets.only(
          left: 12.0,
          right: 8.0,
          top: 4.0,
          bottom:
              MediaQuery.of(context).viewInsets.bottom + 4.0 // 키보드 패딩
          ),
      
      // ✅ 1. Consumer<ChatService>로 감싸서 chatService의 변경 사항을 구독합니다.
      child: Consumer<ChatService>(
        builder: (context, chatService, child) {
          // ✅ 2. chatService의 현재 연결 상태를 가져옵니다.
          final bool isConnected = chatService.isConnected;

          return Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  // ✅ 3. (UX 개선) 연결 상태에 따라 힌트 텍스트 변경
                  decoration: InputDecoration(
                    hintText: isConnected ? '메시지 입력...' : '채팅 연결 중...',
                    border: InputBorder.none,
                    isDense: true, // 높이 줄이기
                  ),
                  // ✅ 4. 연결된 상태에서만 Enter 키로 전송
                  onSubmitted: isConnected ? (_) => _handleSendChat() : null,
                  // ✅ 5. (UX 개선) 연결 안 됐으면 입력창 비활성화
                  enabled: isConnected,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                tooltip: '메시지 전송',
                // ✅ 6. 연결된 상태에서만 전송 버튼 활성화 (null이면 비활성화됨)
                onPressed: isConnected ? _handleSendChat : null,
              ),
            ],
          );
        },
      ),
    );
  }

  // --- 채팅 메시지 전송 핸들러 (기존과 동일) ---
  void _handleSendChat() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return; // 빈 메시지 무시

    // Provider를 통해 ChatService의 sendMessage 호출
    try {
      context.read<ChatService>().sendMessage(text);
      _chatController.clear(); // 전송 성공 시 입력창 비우기
    } catch (e) {
      _showError('메시지 전송 실패: $e');
    }
  }
  // --- ✅ ---

  // 에러 메시지 표시 (SnackBar)
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar(); // 기존 스낵바 닫기
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  // 성공 메시지 표시 (SnackBar)
  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }
} // End of RoomScreenState

