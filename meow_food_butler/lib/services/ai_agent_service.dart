import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:meow_food_butler/models/chat_message.dart';

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
      final result = await _functions
          .httpsCallable('chatWithButler')
          .call<Map<String, dynamic>>({'prompt': prompt});

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
