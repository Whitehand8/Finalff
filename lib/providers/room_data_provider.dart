import 'package:flutter/material.dart';
import 'package:trpg_frontend/models/character.dart';
import 'package:trpg_frontend/models/participant.dart';
import 'package:trpg_frontend/services/room_service.dart';
import 'package:trpg_frontend/services/character_service.dart';

// 1. 방의 모든 데이터(참여자, 캐릭터 시트)를 관리하는 상태 관리자
class RoomDataProvider extends ChangeNotifier {
  // ---------------------------------
  // 상태 (State)
  // ---------------------------------

  String _roomId = '';
  String _roomSystemId = ''; // 현재 방의 룰 (예: 'coc7e', 'dnd5e')
  List<Participant> _participants = [];
  List<Character> _characters = [];
  int _myUserId = -1; // 현재 접속한 유저의 ID
  Participant? _myParticipant; // 현재 접속한 유저의 참여자 정보 (GM 여부 등 확인용)

  bool _isLoading = false;
  String? _error;

  // ---------------------------------
  // 서비스 인스턴스
  // ---------------------------------
  final RoomService _roomService = RoomService();
  final CharacterService _characterService = CharacterService();

  // ---------------------------------
  // 게터 (Getters)
  // ---------------------------------
  String get roomId => _roomId;
  String get roomSystemId => _roomSystemId;
  List<Participant> get participants => List.unmodifiable(_participants);
  List<Character> get characters => List.unmodifiable(_characters);
  Participant? get myParticipant => _myParticipant;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isGM => _myParticipant?.role == 'GM';

  // ---------------------------------
  // 공개 메서드 (Public Methods)
  // ---------------------------------

  /// 방에 입장할 때 호출되어 모든 데이터를 한 번에 불러옵니다.
  /// [myUserId]는 AuthService 등에서 가져온 현재 로그인된 유저의 고유 ID입니다.
  Future<void> fetchData(
      {required String roomId,
      required int myUserId,
      required String systemId}) async {
    _setError(null); // 이전 에러 초기화
    _setLoading(true);

    _roomId = roomId;
    _myUserId = myUserId;
    _roomSystemId = systemId;

    try {
      // 1. 참여자 목록 조회
      final fetchedParticipants = await RoomService.getParticipants(roomId);
      _participants = fetchedParticipants;

      // 2. 내 참여자 정보 저장 (GM 여부 및 내 participantId 확인용)
      _myParticipant = _participants.firstWhere(
        (Participant p) => p.userId == _myUserId,
        orElse: () {
          // 방에 참여자가 아닐 경우 예외 발생 (이론상 발생하면 안 됨)
          throw Exception('현재 유저가 방의 참여자가 아닙니다.');
        },
      );

      // 3. 캐릭터 시트 목록 조회 (N+1 호출)
      // TODO: 향후 백엔드에 /rooms/:roomId/character-sheets 엔드포인트 구현 시 교체
      final futures = _participants.map((p) async {
        try {
          return await _characterService.getCharacter(p.id);
        } catch (e) {
          // 캐릭터 시트가 없는 참여자(404)는 무시
          if (e is CharacterServiceException && e.statusCode == 404) {
            return null;
          }
          // 그 외 에러는 보고
          debugPrint(
              'Failed to get character for participant ${p.id}: $e');
          return null;
        }
      });

      final results = await Future.wait(futures);
      _characters = results.whereType<Character>().toList();

      _setLoading(false);
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
    }
  }

  /// 새로운 캐릭터 시트를 생성합니다.
  /// [participantId]는 시트의 소유주가 될 참여자 ID입니다. (보통 [myParticipant.id])
  Future<void> createSheet(
      {required int participantId,
      required Map<String, dynamic> data}) async {
    _setError(null);
    // TODO: 로딩 상태 추가 (예: _isCreating = true)
    // notifyListeners();

    try {
      final newCharacter = await _characterService.createCharacter(
        participantId: participantId,
        data: data,
        isPublic: isGM, // 기본값: GM이면 public, 아니면 private
      );

      _characters.add(newCharacter); // 상태에 즉시 반영
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      rethrow;
    }
  }

  /// 기존 캐릭터 시트를 업데이트합니다.
  Future<void> updateSheet(
      {required int participantId,
      required Map<String, dynamic> data,
      bool? isPublic}) async {
    _setError(null);
    // TODO: 로딩 상태 추가 (예: _isUpdating[participantId] = true)
    // notifyListeners();

    try {
      final updatedCharacter = await _characterService.updateCharacter(
        participantId: participantId,
        data: data,
        isPublic: isPublic, // GM만 isPublic을 변경할 수 있음 (백엔드에서 처리)
      );

      // 상태에서 기존 시트 찾아서 교체
      final index =
          _characters.indexWhere((c) => c.participantId == participantId);
      if (index != -1) {
        _characters[index] = updatedCharacter;
        notifyListeners();
      }
    } catch (e) {
      _setError(e.toString());
      rethrow;
    }
  }

  // ---------------------------------
  // 내부 헬퍼 (Internal Helpers)
  // ---------------------------------

  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void _setError(String? error) {
    if (_error != error) {
      _error = error;
      notifyListeners();
    }
  }
}