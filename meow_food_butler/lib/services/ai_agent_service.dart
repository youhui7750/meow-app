import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:meow_food_butler/models/chat_message.dart';
import 'package:meow_food_butler/models/chat_session.dart';
import 'package:meow_food_butler/repositories/chat_repo.dart';
import 'package:meow_food_butler/services/location_service.dart';

/// Session-aware chat client. All heavy lifting (Genkit / model calls, prompts,
/// multi-turn history, RAG memory, persistence) lives in the `chatWithButler`
/// Cloud Function. This class:
///   - owns the current session id and the session list ([sessionsStream]),
///   - streams the current session's messages from Firestore ([ChatRepository]),
///   - overlays an optimistic "user msg + Generating…" bubble while awaiting,
///   - forwards a prompt (with userId/sessionId/location/now) to the backend.
///
/// Messages are emitted newest-first to match the chat view's `reverse: true`
/// list. The backend is the single writer of persisted messages.
class ChatService {
  // Firestore/functions region for this project (see firebase.json).
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-east1');

  final ChatRepository _repo;
  final _out = StreamController<List<ChatMessage>>.broadcast();

  String? _sessionId;
  StreamSubscription<List<ChatMessage>>? _messagesSub;

  // Three layers, all newest-first; combined on every emit.
  List<ChatMessage> _notices = []; // sticky (e.g. startup key warning)
  List<ChatMessage> _pending = []; // transient optimistic / error overlay
  List<ChatMessage> _firestore = []; // persisted, from the message stream

  ChatService({ChatRepository? repository})
      : _repo = repository ?? ChatRepository() {
    // Surface a heads-up at startup if a required backend key is missing.
    unawaited(_checkApiKeys());
    // Open the most recent session, or create one if there are none.
    unawaited(_initSession());
  }

  Stream<List<ChatMessage>> get messagesStream => _out.stream;

  /// Seeds [StreamBuilder.initialData] so the UI has data immediately.
  List<ChatMessage> get messages => [..._notices, ..._pending, ..._firestore];

  /// The session list for the history drawer (newest activity first).
  Stream<List<ChatSession>> get sessionsStream => _repo.watchSessions();

  String? get currentSessionId => _sessionId;

  Future<void> _initSession() async {
    try {
      final sessions = await _repo.watchSessions().first;
      if (sessions.isNotEmpty) {
        await switchSession(sessions.first.id);
      } else {
        await startNewSession();
      }
    } catch (_) {
      // Non-fatal: a session is created lazily on the first send anyway.
    }
  }

  /// Point the chat at an existing session and stream its messages.
  Future<void> switchSession(String sessionId) async {
    if (_sessionId == sessionId) return;
    _sessionId = sessionId;
    _pending = [];
    _firestore = [];
    _emit();
    await _messagesSub?.cancel();
    _messagesSub = _repo.watchMessages(sessionId).listen((msgs) {
      _firestore = msgs.reversed.toList(); // oldest-first -> newest-first
      _emit();
    });
  }

  /// Create a fresh session and switch to it.
  Future<void> startNewSession() async {
    final id = await _repo.createSession();
    await switchSession(id);
  }

  Future<void> deleteSession(String sessionId) async {
    final deletingCurrent = _sessionId == sessionId;

    if (deletingCurrent) {
      await _messagesSub?.cancel();
      _messagesSub = null;
      _sessionId = null;
      _pending = [];
      _firestore = [];
      _emit();
    }

    await _repo.deleteSession(sessionId);

    if (deletingCurrent) {
      await _initSession();
    }
  }

  Future<void> _ensureSession() async {
    if (_sessionId == null) await startNewSession();
  }

  List<ChatMessage> _optimistic(String prompt, String assistantText) => [
        ChatMessage(
          senderId: 'ai_agent',
          messageText: assistantText,
          type: ChatMessageType.text,
        ),
        ChatMessage(
          senderId: 'user',
          messageText: prompt,
          type: ChatMessageType.text,
        ),
      ];

  Future<void> fetchPromptResponse(String prompt) async {
    // Resolve location FIRST, before any network await (session creation). On
    // web the geolocation prompt needs the browser's user-gesture activation
    // window; a Firestore round-trip first would consume it and `getCurrentPosition`
    // would be suppressed and return null. Optional — null just means no location.
    final location = await LocationService.tryGetLatLng();

    await _ensureSession();
    final sessionId = _sessionId!;

    // Optimistically show the user's message plus an assistant placeholder.
    _pending = _optimistic(prompt, 'Generating response…');
    _emit();

    try {
      final payload = <String, dynamic>{
        'prompt': prompt,
        'sessionId': sessionId,
      };
      if (location != null) {
        payload['location'] = {
          'latitude': location.latitude,
          'longitude': location.longitude,
        };
      }

      // The model has no internal clock. Send the device's local time as a plain
      // wall-clock reading ("Fri 13:00" → lunch), plus the ISO for date math.
      final now = DateTime.now();
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      payload['now'] = {
        'local': '${weekdays[now.weekday - 1]} $hh:$mm',
        'iso': now.toIso8601String(),
      };

      final result = await _functions
          .httpsCallable('chatWithButler')
          .call<Map<String, dynamic>>(payload);

      final data = result.data;
      if (data['ok'] == true) {
        // Backend persisted user + assistant; the Firestore stream delivers
        // them. Drop the optimistic overlay.
        _pending = [];
      } else {
        // Not persisted on the backend (e.g. quota / key error) — keep the
        // user's message and show the returned reply as a transient bubble.
        _pending = _optimistic(prompt, (data['reply'] as String?) ?? '[No response]');
      }
    } on FirebaseFunctionsException catch (e) {
      _pending =
          _optimistic(prompt, '⚠️ Backend error (${e.code}): ${e.message ?? 'unknown'}');
    } catch (e) {
      _pending = _optimistic(prompt, '⚠️ Could not reach the butler: $e');
    }
    _emit();
  }

  /// Asks the backend whether the required API keys are configured. If any are
  /// missing, shows a sticky heads-up. Best-effort — chat still works if it fails.
  Future<void> _checkApiKeys() async {
    try {
      final result = await _functions
          .httpsCallable('checkApiKeys')
          .call<Map<String, dynamic>>();
      final data = result.data;
      if (data['ok'] == true) return;
      final reply = data['reply'] as String?;
      if (reply == null || reply.isEmpty) return;
      _notices = [
        ChatMessage(
          senderId: 'ai_agent',
          messageText: reply,
          type: ChatMessageType.text,
        ),
      ];
      _emit();
    } catch (_) {
      // Non-fatal: don't block chat if the config check can't be reached.
    }
  }

  void _emit() => _out.add([..._notices, ..._pending, ..._firestore]);

  void dispose() {
    _messagesSub?.cancel();
    _out.close();
  }
}


/// This is AI Agent Service
/// 目前用來抓取地點
/// -- Albert Hsueh, 06/13 13:37
class AiAgentService {
  // 假設你使用的是 OpenAI / Gemini API
  Future<String?> extractRestaurantName(String caption, String location) async {
    final prompt = """
    你是一個美食達人，請從以下 Instagram 貼文內文與打卡地標中，精準提取出「餐廳名稱」與「所在城市或地區」。
    打卡地標: $location
    內文: $caption

    請只回傳最有可能的餐廳名稱與地區（例如："一蘭拉麵 台北信義店" 或 "鼎泰豐 101"），不需要任何額外的解釋或標點符號。如果完全找不到，請回傳 "UNKNOWN"。
    """;

    // 這裡呼叫你的 LLM API (例如 Google GenAI 或 OpenAI)
    // String response = await callLLM(prompt);
    // return response == "UNKNOWN" ? null : response;

    print("[DEBUG] Caption: $caption");
    print("[DEBUG] Location: $location");

    // 💡 臨時測試：如果內文包含 "圍爐烤肉"，就直接回傳正確的搜尋關鍵字
    if (caption.contains("圍爐烤肉")) {
      return "圍爐烤肉 台北市萬華區"; // 這樣 Outscraper 就能精準在地圖上找到了！
    }
    
    // 💡 暫時 Mock 測試用：
    await Future.delayed(const Duration(seconds: 1));
    return "Draft Cafe 台北"; 
  }
}
