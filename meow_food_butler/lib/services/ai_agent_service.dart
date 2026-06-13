import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:meow_food_butler/models/chat_message.dart';
import 'package:meow_food_butler/services/location_service.dart';

/// Thin chat client. All heavy lifting (Genkit / model calls, prompts, history)
/// lives in the `chatWithButler` Cloud Function (`functions/index.js`). This
/// class only: keeps a local message buffer, exposes it as a stream for the UI,
/// forwards a prompt to the backend, and shows whatever the backend returns.
class ChatService {
  // Firestore/functions region for this project (see firebase.json).
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-east1');

  final _messagesStreamController =
      StreamController<List<ChatMessage>>.broadcast();
  // Messages stored in descending order (latest message first).
  final List<ChatMessage> _messages = [];

  Stream<List<ChatMessage>> get messagesStream =>
      _messagesStreamController.stream;

  /// Current messages, used to seed [StreamBuilder.initialData] so the UI has
  /// data immediately instead of waiting on the (broadcast) stream's first
  /// event — which is dropped if emitted before any listener subscribes.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  Future<void> fetchPromptResponse(String prompt) async {
    // Optimistically show the user's message plus an assistant placeholder.
    _messages.insert(
      0,
      ChatMessage(
        senderId: 'user',
        messageText: prompt,
        type: ChatMessageType.text,
      ),
    );
    _messages.insert(
      0,
      ChatMessage(
        senderId: 'ai_agent',
        messageText: 'Generating response…',
        type: ChatMessageType.text,
      ),
    );
    _emit();

    try {
      // Resolve the user's location (prompts for permission the first time) so
      // the backend `whereAmI` tool can answer "where am I?" questions. Optional:
      // if it's null, the agent simply asks the user to enable location.
      final location = await LocationService.tryGetLatLng();

      final payload = <String, dynamic>{'prompt': prompt};
      if (location != null) {
        payload['location'] = {
          'latitude': location.latitude,
          'longitude': location.longitude,
        };
      }

      final result = await _functions
          .httpsCallable('chatWithButler')
          .call<Map<String, dynamic>>(payload);

      final data = result.data;
      // The backend always returns a human-readable `reply`; `code`/`ok`
      // describe the provider state (OK / API_KEY_MISSING / QUOTA_EXCEEDED / …).
      _messages[0] = ChatMessage(
        senderId: 'ai_agent',
        messageText: (data['reply'] as String?) ?? '[No response]',
        type: ChatMessageType.text,
      );
    } on FirebaseFunctionsException catch (e) {
      _messages[0] = ChatMessage(
        senderId: 'ai_agent',
        messageText: '⚠️ Backend error (${e.code}): ${e.message ?? 'unknown'}',
        type: ChatMessageType.text,
      );
    } catch (e) {
      _messages[0] = ChatMessage(
        senderId: 'ai_agent',
        messageText: '⚠️ Could not reach the butler: $e',
        type: ChatMessageType.text,
      );
    }
    _emit();
  }

  void _emit() => _messagesStreamController.add(List.from(_messages));

  void dispose() {
    _messagesStreamController.close();
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
    
    // 💡 暫時 Mock 測試用：
    await Future.delayed(const Duration(seconds: 1));
    return "Draft Cafe 台北"; 
  }
}