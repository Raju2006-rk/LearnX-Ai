import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/app_state_view.dart';
import '../application/chat_controller.dart';
import '../domain/chat.dart';
import 'grammar_feedback_card.dart';

/// The AI Teacher chat screen: a scrolling transcript of message bubbles plus
/// a composer for sending messages. (Requirements 4.1, 4.4)
///
/// Watches [chatControllerProvider] and renders every [ChatMessage] as a
/// bubble — learner messages aligned to the trailing edge, teacher replies to
/// the leading edge. While a reply streams, its bubble is present from the
/// first token and grows as tokens arrive, so the learner sees the reply begin
/// almost immediately (the time-to-first-token target). The composer disables
/// its send control while a send is in flight to avoid overlapping requests,
/// and a failed send surfaces its message in a snack bar.
///
/// The Grammar_Feedback card (task 7.3) and dedicated offline/limit-reached
/// handling (task 7.7) land on top of this screen in later tasks; this task
/// delivers the streaming transcript and composer.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Load the first (newest) page of persisted history once the controller is
    // ready. Paginating keeps the initial read bounded so the screen stays
    // responsive on low-end devices and slow networks. (Requirement 9.3)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(chatControllerProvider.notifier).loadMoreHistory();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    ref.read(chatControllerProvider.notifier).send(text);
  }

  /// The nearest learner message preceding the message at [index] — the
  /// original text an assistant reply corrects. Returns an empty string when
  /// no preceding learner message exists.
  String _precedingUserText(List<ChatMessage> messages, int index) {
    for (var i = index - 1; i >= 0; i--) {
      if (messages[i].role == ChatRole.user) return messages[i].text;
    }
    return '';
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    // Jump after the current frame so the new message is laid out first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Surface a failed send in a snack bar as the error message changes.
    ref.listen<ChatState>(chatControllerProvider, (previous, next) {
      final message = next.errorMessage;
      if (message != null && message != previous?.errorMessage) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
      if (next.messages.length != previous?.messages.length ||
          (next.messages.isNotEmpty &&
              previous?.messages.isNotEmpty == true &&
              next.messages.last.text != previous?.messages.last.text)) {
        _scrollToBottom();
      }
    });

    final messages = ref.watch(
      chatControllerProvider.select((s) => s.messages),
    );
    final isSending = ref.watch(
      chatControllerProvider.select((s) => s.isSending),
    );
    final hasMoreHistory = ref.watch(
      chatControllerProvider.select((s) => s.hasMoreHistory),
    );
    final isLoadingHistory = ref.watch(
      chatControllerProvider.select((s) => s.isLoadingHistory),
    );
    // The live session id, forwarded so a reported feedback item captures the
    // session it belongs to.
    final sessionId = ref.read(chatControllerProvider.notifier).sessionId;

    return Scaffold(
      appBar: AppBar(title: const Text('AI Teacher')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: messages.isEmpty
                  ? const EmptyStateView(
                      icon: Icons.chat_bubble_outline,
                      message: 'Say hello to your AI English teacher.',
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      // A leading load-more row is shown while older history
                      // remains, so the learner can page back on demand rather
                      // than the screen loading the whole conversation at once.
                      itemCount: messages.length + (hasMoreHistory ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (hasMoreHistory && index == 0) {
                          return _LoadMoreHistory(
                            isLoading: isLoadingHistory,
                            onLoad: () => ref
                                .read(chatControllerProvider.notifier)
                                .loadMoreHistory(),
                          );
                        }
                        final messageIndex = hasMoreHistory ? index - 1 : index;
                        return ChatBubble(
                          message: messages[messageIndex],
                          sessionId: sessionId,
                          // The learner's original text a reply corrects is the
                          // nearest preceding user message, captured in a report.
                          originalText: _precedingUserText(
                            messages,
                            messageIndex,
                          ),
                        );
                      },
                    ),
            ),
            _Composer(controller: _input, enabled: !isSending, onSend: _send),
          ],
        ),
      ),
    );
  }
}

/// A single chat message rendered as a bubble, aligned by [ChatRole].
///
/// Learner messages ([ChatRole.user]) align trailing with the primary color;
/// teacher replies ([ChatRole.assistant]) align leading on a surface color. A
/// reply whose text is still empty (the first frame of a streaming reply)
/// shows a small progress indicator so the learner sees the reply has begun.
/// An assistant reply that carries [ChatMessage.grammarFeedback] renders a
/// [GrammarFeedbackCard] beneath its reply text. (Requirements 4.2, 4.3)
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    this.sessionId = '',
    this.originalText = '',
  });

  final ChatMessage message;

  /// The session the message belongs to, forwarded to the feedback card's
  /// report control. Defaults to empty for callers that render a bubble
  /// without feedback context.
  final String sessionId;

  /// The learner's original text an assistant reply corrects, forwarded to the
  /// feedback card's report control.
  final String originalText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.role == ChatRole.user;
    final background = isUser ? scheme.primary : scheme.surfaceContainerHighest;
    final foreground = isUser ? scheme.onPrimary : scheme.onSurface;
    final isStreamingPlaceholder = !isUser && message.text.isEmpty;
    final feedback = message.grammarFeedback;

    final bubble = Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Semantics(
        label: '${isUser ? 'You' : 'Teacher'}: ${message.text}',
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
          ),
          child: isStreamingPlaceholder
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              : Text(
                  message.text,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: foreground),
                ),
        ),
      ),
    );

    // A learner bubble, a streaming placeholder, or a reply without feedback
    // renders as just the bubble. Only a completed reply carrying feedback
    // renders the Grammar_Feedback card beneath it.
    if (isUser || feedback == null) return bubble;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        bubble,
        GrammarFeedbackCard(
          feedback: feedback,
          sessionId: sessionId,
          messageId: message.id ?? '',
          originalText: originalText,
        ),
      ],
    );
  }
}

/// A "load earlier messages" control at the top of the transcript, shown while
/// older persisted history remains. Tapping it fetches the next older page;
/// while a page is in flight it shows a spinner instead. (Requirement 9.3)
class _LoadMoreHistory extends StatelessWidget {
  const _LoadMoreHistory({required this.isLoading, required this.onLoad});

  final bool isLoading;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Center(
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton.icon(
                onPressed: onLoad,
                icon: const Icon(Icons.history),
                label: const Text('Load earlier messages'),
              ),
      ),
    );
  }
}

/// The message composer: a text field plus a send button.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: enabled ? (_) => onSend() : null,
              decoration: const InputDecoration(
                hintText: 'Message your AI teacher',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: enabled ? onSend : null,
            icon: const Icon(Icons.send),
            tooltip: 'Send',
          ),
        ],
      ),
    );
  }
}
