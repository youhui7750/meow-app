import 'package:flutter/material.dart';
import 'package:meow_food_butler/models/chat_message.dart';
import 'package:meow_food_butler/models/chat_session.dart';
import 'package:meow_food_butler/services/ai_agent_service.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Chat();
  }
}

class Chat extends StatefulWidget {
  const Chat({super.key});

  @override
  State<Chat> createState() => _ChatState();
}

class _ChatState extends State<Chat> {
  final TextEditingController _textController = TextEditingController();
  final ChatService _chatService = ChatService();

  @override
  void dispose() {
    _textController.dispose();
    _chatService.dispose();
    super.dispose();
  }

  void _send() {
    if (_textController.text.trim().isNotEmpty) {
      _chatService.fetchPromptResponse(_textController.text.trim());
      _textController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: colorScheme.surfaceContainerHighest,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              child: const Text('🐱'),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Food Butler Meow', style: TextStyle(fontSize: 16)),
                Text(
                  'online',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New chat',
            onPressed: () => _chatService.startNewSession(),
          ),
        ],
      ),
      drawer: _SessionsDrawer(service: _chatService),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _chatService.messagesStream,
              // Seed with the current buffer so we never sit in the `waiting`
              // state with nothing — the broadcast stream's first event is
              // dropped if it fires before this builder subscribes.
              initialData: _chatService.messages,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                // Only show conversational messages (hide developer/system).
                final messages = (snapshot.data ?? const <ChatMessage>[])
                    .where((m) => m.role == 'user' || m.role == 'assistant')
                    .toList();
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'Say hi to your food butler 🐱',
                      style: TextStyle(color: colorScheme.outline),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return _MessageBubble(
                      text: message.text,
                      isMe: message.role == 'user',
                    );
                  },
                );
              },
            ),
          ),
          _Composer(controller: _textController, onSend: _send),
        ],
      ),
    );
  }
}

/// A single chat bubble, styled to match the outlined-box texture of the
/// `_ExperienceCardTile` on the Saved screen: a flat fill with a thin
/// `outlineVariant` border and rounded corners.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.text, required this.isMe});

  final String text;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Warm container tones aligned with the card palette, rather than the
    // saturated `primary`/`surfaceContainerHighest` used before.
    final bubbleColor = isMe
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerLow;
    final textColor = isMe
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;

    const radius = Radius.circular(18);
    final borderRadius = BorderRadius.only(
      topLeft: radius,
      topRight: radius,
      bottomLeft: isMe ? radius : const Radius.circular(4),
      bottomRight: isMe ? const Radius.circular(4) : radius,
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: borderRadius,
          // The outlined box, same as the card's RoundedRectangleBorder side.
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Text(
          text,
          style: TextStyle(color: textColor, fontSize: 15, height: 1.3),
        ),
      ),
    );
  }
}

/// The bottom input bar with a rounded field and circular send button.
class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        color: colorScheme.surfaceContainerHighest,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: const InputDecoration(
                    hintText: 'Message',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: colorScheme.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onSend,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    Icons.send_rounded,
                    color: colorScheme.onPrimary,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// History drawer: lists past chat sessions, plus a "New chat" action. Tapping a
/// session switches the chat to it. Backed by [ChatService.sessionsStream].
class _SessionsDrawer extends StatelessWidget {
  const _SessionsDrawer({required this.service});

  final ChatService service;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Chats',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_comment_outlined),
              title: const Text('New chat'),
              onTap: () {
                service.startNewSession();
                Navigator.of(context).pop();
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<ChatSession>>(
                stream: service.sessionsStream,
                builder: (context, snapshot) {
                  final sessions = snapshot.data ?? const <ChatSession>[];
                  if (sessions.isEmpty) {
                    return Center(
                      child: Text(
                        'No chats yet',
                        style: TextStyle(color: colorScheme.outline),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      final selected = session.id == service.currentSessionId;
                      return ListTile(
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(
                          session.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: selected,
                        selectedTileColor: colorScheme.surfaceContainerHighest,
                        onTap: () {
                          service.switchSession(session.id);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
