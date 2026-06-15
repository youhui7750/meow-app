import 'package:flutter/material.dart';
import 'package:meow_food_butler/models/chat_message.dart';
import 'package:meow_food_butler/models/chat_session.dart';
import 'package:meow_food_butler/models/experience_card.dart';
import 'package:meow_food_butler/models/food_card.dart';
import 'package:meow_food_butler/repositories/restaurant_repository.dart';
import 'package:meow_food_butler/services/ai_agent_service.dart';
import 'package:meow_food_butler/view_models/saved_view_model.dart';
import 'package:meow_food_butler/views/saved/experience_detail_screen.dart';
import 'package:meow_food_butler/views/saved/widgets/experience_card_tile.dart';
import 'package:provider/provider.dart';

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
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    // Client-only command: show the latest dining log as a card (no backend).
    // `/latest-card` shows the most recent meal; `/latest-card ramen` shows the
    // most recent meal matching "ramen" (place name / tag / note).
    final lower = text.toLowerCase();
    if (lower == '/latest-card' || lower.startsWith('/latest-card ')) {
      final query = text.substring('/latest-card'.length).trim();
      _showLatestCard(query: query.isEmpty ? null : query);
      _textController.clear();
      return;
    }

    _chatService.fetchPromptResponse(text);
    _textController.clear();
  }

  /// Inject the most recent logged experience (optionally matching [query]) into
  /// the chat as a tappable card, or a friendly note when there's no match.
  void _showLatestCard({String? query}) {
    final latest = context.read<SavedViewModel>().latestExperience(
          query: query,
        );

    if (latest == null) {
      final what = query == null ? 'any meals' : 'a "$query" meal';
      _chatService.showLocalText("You haven't logged $what yet, nya 🐱");
    } else {
      _chatService.showExperienceCard(latest.id!);
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
                // Only show conversational messages (hide developer/system),
                // and drop blank bubbles — a tool-driven turn can come back with
                // whitespace-only text, which would render as an empty "space"
                // bubble. Experience cards carry no text, so keep those.
                final messages = (snapshot.data ?? const <ChatMessage>[])
                    .where((m) => m.role == 'user' || m.role == 'assistant')
                    .where(
                      (m) =>
                          (m.type == ChatMessageType.experienceCard &&
                              m.experienceId != null) ||
                          (m.type == ChatMessageType.restaurantCards &&
                              m.recommendedSpotIds?.isNotEmpty == true) ||
                          m.text.trim().isNotEmpty,
                    )
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
                    if (message.type == ChatMessageType.experienceCard &&
                        message.experienceId != null) {
                      return _ExperienceCardBubble(
                        experienceId: message.experienceId!,
                      );
                    }
                    if (message.type == ChatMessageType.restaurantCards &&
                        message.recommendedSpotIds?.isNotEmpty == true) {
                      return _RestaurantCardsBubbleV2(
                        restaurantIds: message.recommendedSpotIds!,
                      );
                    }
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
        child: Text.rich(
          TextSpan(
            style: TextStyle(color: textColor, fontSize: 15, height: 1.3),
            children: _parseInlineMarkdown(text),
          ),
        ),
      ),
    );
  }
}

/// An inline dining-log card in the chat. Resolves the [ExperienceCard] live
/// from [SavedViewModel] by id, so edits/deletes reflect immediately. Tapping it
/// opens the same [ExperienceDetailScreen] as the Saved screen.
class _ExperienceCardBubble extends StatelessWidget {
  const _ExperienceCardBubble({required this.experienceId});

  final String experienceId;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final experience = context.watch<SavedViewModel>().experienceById(
          experienceId,
        );

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        child: experience == null
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Text(
                  'This meal is no longer available.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              )
            : ExperienceCardTile(
                experience: experience,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ExperienceDetailScreen(experienceId: experienceId),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Inline restaurant-card results from My Places / imported URLs. The backend
/// sends ExperienceCard ids for now because imported restaurants are stored in
/// the same collection as saved dining entries.
class _RestaurantCardsBubble extends StatelessWidget {
  final List<String> restaurantIds;

  const _RestaurantCardsBubble({required this.restaurantIds});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final savedViewModel = context.watch<SavedViewModel>();
    final experiences = restaurantIds
        .map(savedViewModel.experienceById)
        .whereType<ExperienceCard>()
        .toList();

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.86,
        ),
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: experiences.isEmpty
            ? Text(
                'These restaurant cards are no longer available.',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '想去清單',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ...experiences.map(
                    (experience) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ExperienceCardTile(
                        experience: experience,
                        onTap: () {
                          final id = experience.id;
                          if (id == null) return;
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  ExperienceDetailScreen(experienceId: id),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _RestaurantCardsBubbleV2 extends StatelessWidget {
  final List<String> restaurantIds;

  const _RestaurantCardsBubbleV2({required this.restaurantIds});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final repository = RestaurantRepository();

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.86,
        ),
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: FutureBuilder<List<FoodCard>>(
          future: repository.restaurantsByIds(restaurantIds),
          builder: (context, snapshot) {
            final restaurants = snapshot.data ?? const <FoodCard>[];
            if (snapshot.connectionState != ConnectionState.done) {
              return Text(
                'Loading restaurant cards...',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              );
            }
            if (restaurants.isEmpty) {
              return _RestaurantCardsBubble(restaurantIds: restaurantIds);
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '想去清單',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                ...restaurants.map(
                  (restaurant) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _FoodCardTile(restaurant: restaurant),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FoodCardTile extends StatelessWidget {
  final FoodCard restaurant;

  const _FoodCardTile({required this.restaurant});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final imageUrl =
        restaurant.photoUrls.isEmpty ? null : restaurant.photoUrls.first;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: imageUrl == null
                ? Container(
                    width: 58,
                    height: 58,
                    color: colorScheme.primary,
                    child: Icon(Icons.restaurant, color: colorScheme.onPrimary),
                  )
                : Image.network(
                    imageUrl,
                    width: 58,
                    height: 58,
                    fit: BoxFit.cover,
                    webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 58,
                      height: 58,
                      color: colorScheme.primary,
                      child:
                          Icon(Icons.restaurant, color: colorScheme.onPrimary),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  restaurant.primaryTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (restaurant.rating != null)
                      Text(
                        '★ ${restaurant.rating!.toStringAsFixed(1)}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.amber.shade800,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    if (restaurant.priceRange?.isNotEmpty == true)
                      Text(
                        restaurant.priceRange!,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    Text(
                      restaurant.visited ? '已去過' : '想去',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                if (restaurant.formattedAddress?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    restaurant.formattedAddress!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (restaurant.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: restaurant.tags.take(3).map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: colorScheme.outlineVariant),
                        ),
                        child: Text(
                          '#$tag',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Converts the inline Markdown the LLM emits (`**bold**`, `*italic*`) into
/// styled [TextSpan]s. The bubble's parent [TextSpan] supplies colour/size; the
/// styles here only layer on weight/slant so they merge cleanly. Anything that
/// isn't a complete `**…**`/`*…*` pair is left verbatim, so stray asterisks are
/// shown as-is rather than swallowed.
List<InlineSpan> _parseInlineMarkdown(String text) {
  final pattern = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*');
  final spans = <InlineSpan>[];
  var last = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > last) {
      spans.add(TextSpan(text: text.substring(last, match.start)));
    }
    final bold = match.group(1);
    if (bold != null) {
      spans.add(TextSpan(
        text: bold,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ));
    } else {
      spans.add(TextSpan(
        text: match.group(2),
        style: const TextStyle(fontStyle: FontStyle.italic),
      ));
    }
    last = match.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last)));
  }
  return spans;
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

  Future<void> _confirmDelete(
    BuildContext context,
    ChatSession session,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete chat?'),
          content: Text(
            'Delete "${session.displayTitle}" and all of its messages?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await service.deleteSession(session.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat deleted')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete chat: $error')),
      );
    }
  }

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
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete chat',
                          onPressed: () => _confirmDelete(context, session),
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
