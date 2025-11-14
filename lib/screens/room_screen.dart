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
// --- 🚨 [신규] (기능 1) 토큰 생성 모달 Import ---
import 'package:trpg_frontend/widgets/vtt/create_token_modal.dart';
// --- 🚨 [신규 끝] ---

// --- ✅ 3. Dice 관련 Import 추가 ---
import 'package:trpg_frontend/widgets/dice/dice_roll_modal.dart';
// --- ✅ ---

// ▼▼▼ [수정 1] Provider 및 Panel 임포트 추가 ▼▼▼
import 'package:trpg_frontend/providers/room_data_provider.dart';
import 'package:trpg_frontend/widgets/room/participant_character_panel.dart';
// ▲▲▲ [수정 1 끝] ▲▲▲

class RoomScreen extends StatefulWidget {
  final Room room;
  const RoomScreen({super.key, required this.room});

  // --- Provider 제공 (수정됨) ---
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
        ChangeNotifierProvider(
          create: (_) => NpcProvider(room.id!), // 생성 시 roomId 전달 및 NPC 로딩 시작
        ),
        ChangeNotifierProvider(
          create: (_) => ChatService(room.chatRoomId!), // 채팅방의 숫자 ID 전달
        ),
        ChangeNotifierProvider(
          create: (_) => VttSocketService(
            roomId: room.id!, 
            onRoomEvent: (eventName, data) {
              debugPrint('[VTT Room Event] $eventName: $data');
            },
          ),
        ),
        // ▼▼▼ [수정 2] RoomDataProvider 주입 (사용자가 이미 적용함) ▼▼▼
        ChangeNotifierProvider(
          create: (context) {
            return RoomDataProvider();
          },
        ),
        // ▲▲▲ [수정 2 끝] ▲▲▲
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
  // List<Participant> _participants = []; // <-- [수정 3] Provider가 관리하므로 삭제
  // bool _isParticipantsLoading = false; // <-- [수정 4] Provider가 관리하므로 삭제

  bool _isCurrentUserGm = false;
  int? _currentUserId; 

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _room = widget.room;
    _initializeScreen(); 
  }

  // --- ✨ 초기화 함수 (수정됨) ---
  Future<void> _initializeScreen() async {
    // VTT 소켓 자동 연결
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<VttSocketService>().connect();
        debugPrint('[RoomScreen] VTT Socket connect() 호출됨');
      }
    });

    await _loadCurrentUserId(); // AuthService에서 사용자 ID 가져오기
    
    // ▼▼▼ [수정 5] Provider로 데이터 로드 (사용자가 이미 적용함) ▼▼▼
    if (mounted && _currentUserId != null) {
      // Room 모델에 trpgType 필드가 있다고 가정합니다.
      // 만약 Room 모델에 trpgType이 없다면 _room.trpgType 대신 "coc7e" 등 룰 ID 문자열을 직접 전달해야 합니다.
      await context.read<RoomDataProvider>().fetchData(
            roomId: _room.id!,
            myUserId: _currentUserId!,
            systemId: _room.trpgType, // 👈 _room.trpgType 사용
          );
      
      if (mounted) {
        setState(() {
          _isCurrentUserGm = context.read<RoomDataProvider>().isGM;
        });
      }
    }
    // ▲▲▲ [수정 5 끝] ▲▲▲
  }

  // --- ✨ 현재 사용자 ID 로드 함수 (기존과 동일) ---
  Future<void> _loadCurrentUserId() async {
    final userId = await AuthService.instance.getCurrentUserId();
    if (mounted) {
      setState(() {
        _currentUserId = userId; // 상태 변수에 저장
      });
    }
  }

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
      
      // ▼▼▼ [수정 6] _loadParticipants() 대신 Provider.fetchData() 호출 ▼▼▼
      // _loadParticipants(); 
      if (mounted && _currentUserId != null) {
         context.read<RoomDataProvider>().fetchData(
              roomId: _room.id!,
              myUserId: _currentUserId!,
              systemId: _room.trpgType,
            );
      }
      // ▲▲▲ [수정 6 끝] ▲▲▲
      
      context.read<VttSocketService>().connect(); // VTT 연결 재시도
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

  // ▼▼▼ [수정 7] _loadParticipants() 메서드 전체 삭제 ▼▼▼
  /*
  Future<void> _loadParticipants() async {
    // ... (이 메서드 전체 삭제) ...
  }
  */
  // ▲▲▲ [수정 7 끝] ▲▲▲

  // ▼▼▼ [수정 8] _checkCurrentUserRole() 메서드 전체 삭제 ▼▼▼
  /*
  void _checkCurrentUserRole() {
    // ... (이 메서드 전체 삭제) ...
  }
  */
  // ▲▲▲ [수정 8 끝] ▲▲▲


  // --- 🚨 [복원됨] 방 관리 함수들 (수정됨) ---
  Future<void> _leaveRoom() async {
    if (_room.creatorId == _currentUserId) {
      _showCannotLeaveAsCreatorDialog();
      return;
    }
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
              Navigator.of(context).pop(); 
              try {
                await RoomService.leaveRoom(_room.id!);
                if (!mounted) return;
                _showSuccess('방에서 나갔습니다.');
                context.go(Routes.rooms); 
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
              Navigator.of(context).pop(); 
              try {
                await RoomService.deleteRoom(_room.id!);
                if (!mounted) return;
                _showSuccess('방이 삭제되었습니다.');
                context.go(Routes.rooms); 
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
       _validateRoomStillExists(); 
       
       // ▼▼▼ [수정 9] _loadParticipants() 대신 Provider.fetchData() 호출 ▼▼▼
       if (mounted && _currentUserId != null) {
         await context.read<RoomDataProvider>().fetchData(
              roomId: _room.id!,
              myUserId: _currentUserId!,
              systemId: _room.trpgType,
            );
          if (mounted) {
            setState(() { _isCurrentUserGm = context.read<RoomDataProvider>().isGM; });
          }
       }
       // ▲▲▲ [수정 9 끝] ▲▲▲
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
          participantId.toString(), newRole); 
      if (!mounted) return;
      _showSuccess('역할이 변경되었습니다.');
      
      // ▼▼▼ [수정 10] _loadParticipants() 대신 Provider.fetchData() 호출 ▼▼▼
      if (mounted && _currentUserId != null) {
         await context.read<RoomDataProvider>().fetchData(
              roomId: _room.id!,
              myUserId: _currentUserId!,
              systemId: _room.trpgType,
            );
          if (mounted) {
            setState(() { _isCurrentUserGm = context.read<RoomDataProvider>().isGM; });
          }
       }
      // ▲▲▲ [수정 10 끝] ▲▲▲
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
    final participantIdController = TextEditingController(); 
    final roleController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('참여자 역할 변경'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField( 
                controller: participantIdController,
                keyboardType: TextInputType.number, 
                decoration:
                    const InputDecoration(labelText: 'Participant ID')), 
            TextField( 
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
                  roleController.text.trim().toUpperCase(); 
              final participantId = int.tryParse(idText); 

              if (participantId == null) {
                _showError('유효한 Participant ID를 입력해주세요.');
                return;
              }
              if (roleText != 'GM' && roleText != 'PLAYER') {
                _showError('역할은 GM 또는 PLAYER 여야 합니다.');
                return;
              }
              Navigator.of(context).pop(); 
              _updateParticipantRole(participantId, roleText); 
            },
            child: const Text('변경'),
          ),
        ],
      ),
    );
  }
  // --- 🚨 [복원 끝] ---


  // --- 🚨 [복원됨] NPC 관련 UI 호출 함수 ---
  void _showNpcListModal() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        // [수정] 다이얼로그가 RoomScreen의 Provider에 접근하도록 .value 생성자 사용
        return ChangeNotifierProvider.value(
          value: context.read<NpcProvider>(),
          child: Consumer<NpcProvider>(
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
                                    Navigator.pop(dialogContext); 
                                    _showNpcDetailModal(npc);   
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
          ),
        );
      },
    );
  }

  void _showNpcDetailModal(Npc npc) {
    showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<NpcProvider>(), 
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
        value: context.read<NpcProvider>(), 
        child: NpcCreateModal(roomId: _room.id!),
      ),
    );
  }
  // --- 🚨 [복원 끝] ---

  // --- 🔴 [수정됨] VTT 맵 선택 모달 (Provider 전달) ---
  void _showMapSelectModal() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return ChangeNotifierProvider.value(
          value: context.read<VttSocketService>(),
          child: MapSelectModal(
            roomId: _room.id!,
            isGm: _isCurrentUserGm,
          ),
        );
      },
    );
  }
  // --- 🔴 [수정 끝] ---


  // --- ✅ 주사위 굴림 모달 호출 함수 (수정됨) ---
  void _showDiceRollModal() {
    String nickname = '참여자';
    
    // ▼▼▼ [수정 11] Provider에서 '내 참여자 정보'를 가져와서 사용 ▼▼▼
    final myParticipant = context.read<RoomDataProvider>().myParticipant;
    if (myParticipant != null) {
      nickname = myParticipant.nickname;
    }
    // ▲▲▲ [수정 11 끝] ▲▲▲

    showDialog(
      context: context,
      builder: (dialogContext) {
        // 📌 [수정] 채팅 서비스도 다이얼로그에 전달합니다.
        return ChangeNotifierProvider.value(
          value: context.read<ChatService>(),
          child: DiceRollModal(rollerNickname: nickname),
        );
      },
    );
  }
  
  // --- 🚨 [신규] (기능 1) 사진 삽입(토큰 생성) 모달 호출 ---
  void _showCreateTokenModal() {
    final vttSocket = context.read<VttSocketService>();
    // 씬(맵)에 입장한 상태인지 확인
    if (vttSocket.scene == null) {
      _showError('맵에 먼저 입장해야 이미지를 추가할 수 있습니다.');
      return;
    }
    
    // GM만 토큰을 생성할 수 있게 제한
    if (!_isCurrentUserGm) {
      _showError('GM만 이미지 토큰을 추가할 수 있습니다.');
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        // 📌 [수정] VttSocketService를 다이얼로그에 전달합니다.
        return ChangeNotifierProvider.value(
          value: vttSocket, // 이미 위에서 read()로 가져왔으므로 재사용
          child: const CreateTokenModal(),
        );
      },
    );
  }
  // --- 🚨 [신규 끝] ---


  // --- 🚨 [신규] (기능 3) 격자 토글 함수 ---
  void _toggleGrid() {
    final vttSocket = context.read<VttSocketService>();
    final currentScene = vttSocket.scene;

    if (currentScene == null) {
      _showError('맵에 입장한 상태에서만 격자를 변경할 수 있습니다.');
      return;
    }
    
    if (!_isCurrentUserGm) {
      _showError('격자 설정은 GM만 변경할 수 있습니다.');
      return;
    }

    // vtt_scene.dart에 추가한 copyWith 메서드 사용
    final updatedScene = currentScene.copyWith(
      showGrid: !currentScene.showGrid, // 현재 상태를 반전
    );

    // vtt_socket_service의 sendMapUpdate 호출
    vttSocket.sendMapUpdate(updatedScene);
  }
  // --- 🚨 [신규 끝] ---


  // === UI 빌드 ===
  @override
  Widget build(BuildContext context) {
    final npcError = context.select((NpcProvider p) => p.error);
    if (npcError != null && ModalRoute.of(context)?.isCurrent == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showError('NPC 오류: $npcError');
        context.read<NpcProvider>().clearError(); 
      });
    }

    final bool isGridVisible = context.watch<VttSocketService>().scene?.showGrid ?? true;

    return Scaffold(
      key: _scaffoldKey,
      // --- 🚨 [수정됨] AppBar에 새 기능 버튼 추가 ---
      appBar: AppBar(
        title: Text(_room.name),
        backgroundColor: const Color(0xFF8C7853), 
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(), 
        ),
        actions: [
          // 주사위
          IconButton(
            icon: const Icon(Icons.casino),
            tooltip: '주사위 굴리기',
            onPressed: _showDiceRollModal, 
          ),

          // --- 🚨 [신규] (기능 3) 격자 토글 버튼 ---
          IconButton(
            icon: Icon(isGridVisible ? Icons.grid_on : Icons.grid_off),
            tooltip: '격자 보이기/숨기기',
            onPressed: _toggleGrid, // [신규] 핸들러 연결
          ),

          // --- 🚨 [신규] (기능 1) 사진 삽입 버튼 ---
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            tooltip: '이미지 토큰 추가',
            onPressed: _showCreateTokenModal, // [신규] 핸들러 연결
          ),
          
          // 맵 선택
          IconButton(
            icon: const Icon(Icons.map_outlined), 
            tooltip: '맵 선택/로드',
            onPressed: _showMapSelectModal, 
          ),

          // NPC 목록
          IconButton(
            icon: const Icon(Icons.book_outlined), 
            tooltip: 'NPC 목록',
            onPressed: _showNpcListModal, // [복원됨]
          ),
          
          // 참여자 목록
          IconButton(
            icon: const Icon(Icons.people),
            tooltip: '참여자 목록',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
          
          // 방 관리 메뉴
          PopupMenuButton<String>(
            onSelected: (value) {
              // [복원됨]
              switch (value) {
                case 'leave': _showLeaveRoomDialog(); break;
                case 'delete': _showDeleteRoomDialog(); break;
                case 'transfer': _showTransferCreatorDialog(); break;
                case 'updateRole': _showUpdateRoleDialog(); break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'leave',
                child: ListTile(leading: Icon(Icons.exit_to_app), title: Text('방 나가기')),
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
        ],
      ),
      // --- 🚨 [수정 끝] ---
      
      body: Consumer<NpcProvider>(
          builder: (context, npcProvider, child) {
        if (npcProvider.isLoading && npcProvider.npcs.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return Stack(
          children: [
            const Positioned.fill(child: VttCanvas()), // [수정] VttCanvas -> VTTCanvas
            
            // ▼▼▼ [수정 12] Consumer로 Provider의 participants를 ChatListWidget에 전달 ▼▼▼
            
              Positioned(     // 👈 1. 'Positioned.fill'을 'Positioned'로 변경
                // --- 2. 채팅창의 위치와 크기를 강제로 지정 ---
                bottom: 80,     // 하단 채팅 입력창 바로 위에 위치 (값은 조절 필요)
                left: 20,       // VTT와 겹치도록 좌우 여백
                right: 20,
                height: 300,
                child:IgnorePointer(
                  child:Consumer<RoomDataProvider>(
                    builder: (context, roomData, child) {
                      return ChatListWidget(
                      participants: roomData.participants,
                      currentUserId: _currentUserId,
                    );
                  }
                ),
            // ▲▲▲ [수정 12 끝] ▲▲▲
              ),
            ),
          ],
        );
      }),
      
      // --- 🚨 참여자 Drawer (수정됨) ---
      endDrawer: Drawer(
        child: Column(
          children: [
            AppBar(
                title: const Text('참여자'), automaticallyImplyLeading: false, 
                backgroundColor: const Color(0xFF8C7853)
            ),
            
            // ▼▼▼ [수정 13] ListTile을 Consumer로 감싸서 Provider와 연동 ▼▼▼
            Consumer<RoomDataProvider>(
              builder: (context, provider, child) {
                return ListTile(
                  title: const Text('참여자 및 시트'), // <-- 제목 수정
                  trailing: provider.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: '새로고침',
                          onPressed: () {
                            if (_currentUserId != null) {
                              // Provider를 통해 데이터 새로고침
                              provider.fetchData(
                                roomId: _room.id!,
                                myUserId: _currentUserId!,
                                systemId: _room.trpgType,
                              );
                            }
                          }
                        ),
                );
              },
            ),
            // ▲▲▲ [수정 13 끝] ▲▲▲

            // ▼▼▼ [수정 14] 기존 ListView.builder를 ParticipantCharacterPanel로 교체 ▼▼▼
            const Expanded(
              child: ParticipantCharacterPanel(),
            ),
            // ▲▲▲ [수정 14 끝] ▲▲▲
          ],
        ),
      ),
      // --- 🚨 [수정 끝] ---

      bottomNavigationBar: _buildBottomBar(),
      
      // --- 🚨 [복원됨] NPC 생성 버튼 ---
      floatingActionButton: _isCurrentUserGm
    // 1. VttSocketService의 상태를 실시간으로 감시하기 위해 Consumer로 감쌉니다.
    ? Consumer<VttSocketService>(
        builder: (context, vttSocket, child) {
          // 2. vttSocket에서 현재 업로드 중인지 상태를 가져옵니다.
          final bool isUploading = vttSocket.isUploading;

          // 3. Row를 사용해 버튼을 가로로 나란히 배치합니다.
          return Row(
            mainAxisSize: MainAxisSize.min, // Row가 필요한 만큼만 공간 차지
            mainAxisAlignment: MainAxisAlignment.end, // 오른쪽 정렬
            children: [
              // 4. [신규] 맵에 이미지 업로드 버튼 (요청하신 버튼)
              FloatingActionButton(
                onPressed: isUploading
                    ? null // 업로드 중이면 버튼 비활성화
                    : () {
                        // 5. vtt_socket_service의 triggerImageUpload 함수를 호출합니다.
                        vttSocket.triggerImageUpload();
                      },
                tooltip: '맵에 이미지 업로드',
                // 6. Hero 태그는 화면 전환 애니메이션을 위해 고유해야 합니다.
                heroTag: 'fab-add-map-image',
                backgroundColor: isUploading
                    ? Colors.grey // 업로드 중이면 회색
                    : Colors.blueGrey[600],
                child: isUploading
                    // 업로드 중이면 로딩 아이콘 표시
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      )
                    : const Icon(Icons.add_photo_alternate),
              ),

              // 7. [간격] 요청하신 '약간의 간격'
              const SizedBox(width: 8),

              // 8. [기존] NPC 생성 버튼
              FloatingActionButton(
                onPressed: _showCreateNpcModal,
                tooltip: 'NPC 생성',
                heroTag: 'fab-add-npc', // 6. Hero 태그 고유하게 설정
                backgroundColor: Colors.brown[700],
                // 아이콘을 좀 더 명확한 것으로 변경 (선택 사항)
                child: const Icon(Icons.person_add_alt_1),
              ),
            ],
          );
        },
      )
    : null, // GM이 아니면 아무 버튼도 보이지 않음
floatingActionButtonLocation:
    FloatingActionButtonLocation.endDocked,
      // --- 🚨 [복원 끝] ---
    );
  }

  // --- 🚨 [복원됨] 하단 바 및 채팅 함수 ---
  Widget _buildBottomBar() {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(), 
      notchMargin: 6.0, 
      child: _buildBottomChatBar(),
    );
  }

  Widget _buildBottomChatBar() {
    return Container(
      padding: EdgeInsets.only(
          left: 12.0,
          right: 8.0,
          top: 4.0,
          bottom:
              MediaQuery.of(context).viewInsets.bottom + 4.0 
          ),
      
      child: Consumer<ChatService>(
        builder: (context, chatService, child) {
          final bool isConnected = chatService.isConnected;

          return Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  decoration: InputDecoration(
                    hintText: isConnected ? '메시지 입력...' : '채팅 연결 중...',
                    border: InputBorder.none,
                    isDense: true, 
                  ),
                  onSubmitted: isConnected ? (_) => _handleSendChat() : null,
                  enabled: isConnected,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                tooltip: '메시지 전송',
                onPressed: isConnected ? _handleSendChat : null,
              ),
            ],
          );
        },
      ),
    );
  }

  void _handleSendChat() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return; 

    try {
      context.read<ChatService>().sendMessage(text);
      _chatController.clear(); 
    } catch (e) {
      _showError('메시지 전송 실패: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar(); 
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }
  // --- 🚨 [복원 끝] ---
} // End of RoomScreenState