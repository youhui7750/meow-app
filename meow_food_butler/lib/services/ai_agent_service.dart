import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
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

  // Four layers, all newest-first; combined on every emit.
  List<ChatMessage> _notices = []; // sticky (e.g. startup key warning)
  List<ChatMessage> _pending = []; // transient optimistic / error overlay
  List<ChatMessage> _local = []; // client-injected UI (e.g. /latest-card), not persisted
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
  List<ChatMessage> get messages => _composed();

  /// Merge the buffers into the single newest-first list the view renders.
  ///
  /// `_pending`, `_local`, and `_firestore` share ONE timeline ordered by
  /// timestamp, so a client-injected card (`_local`) sits where it was shown in
  /// time rather than in a fixed layer. Previously the card lived in a layer
  /// that always sorted between `_pending` and `_firestore`; when a turn moved
  /// from the optimistic overlay to the persisted stream it crossed to the
  /// other side of the card, making the card jump up/down. `_notices` (the
  /// sticky key warning) stays pinned at the bottom.
  List<ChatMessage> _composed() {
    final timeline = [..._pending, ..._local, ..._firestore];
    // Stable newest-first sort: Dart's List.sort isn't stable, so decorate with
    // the original index and break ties on it. That keeps equal-timestamp items
    // (e.g. the optimistic user+assistant pair) in their intended order.
    final order = List<int>.generate(timeline.length, (i) => i);
    order.sort((a, b) {
      final byTime = timeline[b].timestamp.compareTo(timeline[a].timestamp);
      return byTime != 0 ? byTime : a.compareTo(b);
    });
    return [..._notices, ...order.map((i) => timeline[i])];
  }

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
    _local = [];
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
      _local = [];
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

  List<ChatMessage> _optimistic(String prompt, String assistantText) {
    // Construct the user turn FIRST so it gets the earlier timestamp; the
    // assistant reply (constructed next) is newer and sorts below it in
    // [_composed]. The returned order is newest-first and also acts as the
    // tie-break when the two timestamps land in the same instant.
    final user = ChatMessage(
      senderId: 'user',
      messageText: prompt,
      type: ChatMessageType.text,
    );
    final assistant = ChatMessage(
      senderId: 'ai_agent',
      messageText: assistantText,
      type: ChatMessageType.text,
    );
    return [assistant, user];
  }

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
        // Apply any client UI actions the agent requested this turn (e.g. show
        // a dining-log card its viewDiningLog tool looked up).
        // ignore: avoid_print
        print('[DEBUG] chatWithButler actions: ${data['actions']}');
        _applyActions(data['actions']);
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

  /// Apply client UI actions returned by `chatWithButler`. Currently just
  /// `showExperienceCard` — the agent's `viewDiningLog` tool resolves a logged
  /// meal and asks the client to inject its card by id, so natural-language
  /// requests ("the last time I ate ramen") land on the same path as the
  /// `/latest-card` command. Cloud Functions decodes nested JSON as
  /// `List`/`Map<Object?, Object?>`, so match loosely.
  void _applyActions(dynamic actions) {
    if (actions is! List) return;
    final seen = <String>{}; // dedupe repeated cards within one turn
    for (final action in actions) {
      if (action is! Map) continue;
      if (action['type'] == 'showExperienceCard') {
        final id = action['experienceId'];
        if (id is String && id.isNotEmpty && seen.add(id)) {
          showExperienceCard(id);
        }
      } else if (action['type'] == 'showRestaurantCards') {
        final ids = action['experienceIds'] ??
            action['ids'] ??
            action['recommendedSpotIds'];
        if (ids is List) {
          final experienceIds = ids
              .whereType<String>()
              .where((id) => id.isNotEmpty && seen.add(id))
              .toList();
          if (experienceIds.isNotEmpty) {
            showRestaurantCards(experienceIds);
          }
        }
      }
    }
  }

  /// Inject a dining-log card into the chat locally (no backend call). The card
  /// references an [ExperienceCard] by id; the view resolves it live from
  /// `SavedViewModel`. Ephemeral: cleared when the session changes.
  void showExperienceCard(String experienceId) {
    _local = [
      ChatMessage(
        senderId: 'ai_agent',
        messageText: '',
        type: ChatMessageType.experienceCard,
        experienceId: experienceId,
      ),
      ..._local,
    ];
    _emit();
  }

  /// Inject a small set of saved/imported restaurant cards into the chat. These
  /// are backed by ExperienceCard ids because My Places currently stores
  /// imported restaurant cards in the same Firestore collection.
  void showRestaurantCards(List<String> experienceIds) {
    _local = [
      ChatMessage(
        senderId: 'ai_agent',
        messageText: '',
        type: ChatMessageType.restaurantCards,
        timestamp: Timestamp.fromDate(
          DateTime.now().add(const Duration(seconds: 2)),
        ),
        recommendedSpotIds: List.unmodifiable(experienceIds),
      ),
      ..._local,
    ];
    _emit();
  }

  /// Inject a plain assistant text bubble locally (e.g. "no meals logged yet").
  void showLocalText(String text) {
    _local = [
      ChatMessage(
        senderId: 'ai_agent',
        messageText: text,
        type: ChatMessageType.text,
      ),
      ..._local,
    ];
    _emit();
  }

  void _emit() => _out.add(_composed());

  void dispose() {
    _messagesSub?.cancel();
    _out.close();
  }
}
