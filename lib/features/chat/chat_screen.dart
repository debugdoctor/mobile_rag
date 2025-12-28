import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:share_plus/share_plus.dart';

import '../../app_providers.dart';
import '../../core/i18n.dart';
import '../../domain/models.dart';
import '../../services/rag_service.dart';
import '../../widgets/rag_visualization.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  List<Message> _messages = [];
  List<Conversation> _conversations = [];
  List<KnowledgeBase> _knowledgeBases = [];
  String? _conversationId;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isLoadingConversations = false;
  bool _isLoadingKnowledge = false;
  String _chatModel = '';
  List<String> _chatModels = [];
  List<String> _selectedKnowledgeBaseIds = [];
  final Set<String> _expandedEvidence = {};
  String? _streamingMessageId;

  bool _showVisualization = false;
  RagVisualizationStep _visualizationStep = RagVisualizationStep.query;
  RagVisualizationData _visualizationData = RagVisualizationData(
    query: '',
    candidates: [],
    selectedEvidence: [],
    context: '',
    prompt: '',
    answer: '',
    embedding: RagVisualizationEmbedding(enabled: true),
  );

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    await Future.wait([
      _loadConversation(),
      _loadConversations(),
      _loadKnowledgeBases(),
      _loadModels(),
    ]);
  }

  Future<void> _loadModels() async {
    final storage = ref.read(storageServiceProvider);
    final ai = await storage.getAiConfig();
    if (!mounted) {
      return;
    }
    setState(() {
      _chatModel = ai.model;
      _chatModels = ai.models;
    });
  }

  Future<void> _loadConversations() async {
    setState(() {
      _isLoadingConversations = true;
    });
    final rag = ref.read(ragServiceProvider);
    final list = await rag.listConversations();
    if (!mounted) {
      return;
    }
    setState(() {
      _conversations = list;
      _isLoadingConversations = false;
    });
  }

  Future<void> _loadKnowledgeBases() async {
    setState(() {
      _isLoadingKnowledge = true;
    });
    final rag = ref.read(ragServiceProvider);
    final list = await rag.listKnowledgeBases();
    if (!mounted) {
      return;
    }
    setState(() {
      _knowledgeBases = list;
      _isLoadingKnowledge = false;
    });
  }

  Future<void> _loadConversation() async {
    final rag = ref.read(ragServiceProvider);
    final latest = await rag.getLatestConversation();
    if (!mounted) {
      return;
    }
    if (latest == null) {
      setState(() {
        _messages = [];
        _conversationId = null;
        _isLoading = false;
      });
      return;
    }
    final history = await rag.listMessages(latest.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _conversationId = latest.id;
      _messages = history;
      _isLoading = false;
    });
    _scrollToBottom();
  }

  Future<void> _switchConversation(Conversation conversation) async {
    setState(() {
      _conversationId = conversation.id;
      _isLoading = true;
    });
    final rag = ref.read(ragServiceProvider);
    final history = await rag.listMessages(conversation.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _messages = history;
      _isLoading = false;
    });
    _scrollToBottom();
  }

  Future<void> _createConversation() async {
    final locale = ref.read(localeControllerProvider).locale;
    final rag = ref.read(ragServiceProvider);
    final conversation = await rag.createConversation(translate(locale, 'chat.conversation.defaultTitle'));
    await _loadConversations();
    await _switchConversation(conversation);
  }

  Future<void> _deleteConversation(Conversation conversation) async {
    final locale = ref.read(localeControllerProvider).locale;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(translate(locale, 'chat.conversation.deleteTitle')),
        content: Text(translate(locale, 'chat.conversation.deleteMessage', {'title': conversation.title ?? ''})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(translate(locale, 'common.cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: Text(translate(locale, 'common.delete')),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final rag = ref.read(ragServiceProvider);
    await rag.deleteConversation(conversation.id);
    await _loadConversations();
    if (_conversationId == conversation.id) {
      await _loadConversation();
    }
  }

  Future<void> _handleSend() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) {
      return;
    }
    final rag = ref.read(ragServiceProvider);
    setState(() {
      _isSending = true;
    });

    var conversationId = _conversationId;
    if (conversationId == null) {
      final conversation = await rag.createConversation(text.substring(0, text.length > 40 ? 40 : text.length));
      conversationId = conversation.id;
      _conversationId = conversationId;
      await _loadConversations();
    }

    final userMessage = await rag.addMessage(conversationId, MessageRole.user, text);
    setState(() {
      _messages = [..._messages, userMessage];
      _inputController.clear();
    });

    if (_messages.where((msg) => msg.role == MessageRole.user).length == 1) {
      await rag.updateConversation(
        conversationId,
        title: text.substring(0, text.length > 40 ? 40 : text.length),
        summary: _buildSummary(text),
        touch: false,
      );
      await _loadConversations();
    }

    final streamingId = 'stream_${DateTime.now().millisecondsSinceEpoch}';
    var streamMessage = Message(id: streamingId, role: MessageRole.assistant, content: '');
    setState(() {
      _messages = [..._messages, streamMessage];
      _streamingMessageId = streamingId;
    });
    _scrollToBottom();

    final embeddingModel = _resolveEmbeddingModel();
    final knowledgeBaseIds = _selectedKnowledgeBaseIds.isEmpty ? null : _selectedKnowledgeBaseIds;

    setState(() {
      _visualizationStep = RagVisualizationStep.query;
      _visualizationData = RagVisualizationData(
        query: text,
        candidates: [],
        selectedEvidence: [],
        context: '',
        prompt: '',
        answer: '',
        embedding: RagVisualizationEmbedding(enabled: true),
      );
    });

    try {
      final response = await rag.sendMessageStreamWithVisualization(
        conversationId,
        text,
        (chunk) {
          setState(() {
            streamMessage = Message(
              id: streamingId,
              role: MessageRole.assistant,
              content: chunk,
            );
            _messages = _messages.map((msg) => msg.id == streamingId ? streamMessage : msg).toList();
          });
          _scrollToBottom();
        },
        (step, data) {
          setState(() {
            _visualizationStep = step;
            _visualizationData = data;
          });
        },
        knowledgeBaseIds: knowledgeBaseIds,
        embeddingModel: embeddingModel,
      );
      setState(() {
        _messages = _messages.map((msg) => msg.id == streamingId ? response : msg).toList();
        _streamingMessageId = null;
      });
    } catch (error) {
      setState(() {
        _messages = _messages.map((msg) {
          if (msg.id == streamingId) {
            return Message(id: streamingId, role: MessageRole.system, content: error.toString());
          }
          return msg;
        }).toList();
        _streamingMessageId = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  String? _resolveEmbeddingModel() {
    final ids = _selectedKnowledgeBaseIds.isEmpty
        ? _knowledgeBases.map((kb) => kb.id).toList()
        : _selectedKnowledgeBaseIds;
    if (ids.isEmpty) {
      return null;
    }
    String? resolved;
    for (final id in ids) {
      KnowledgeBase? kb;
      for (final item in _knowledgeBases) {
        if (item.id == id) {
          kb = item;
          break;
        }
      }
      if (kb == null) {
        continue;
      }
      final model = kb.embeddingModel?.trim() ?? '';
      if (model.isEmpty) {
        return null;
      }
      resolved ??= model;
      if (resolved != model) {
        return null;
      }
    }
    return resolved;
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _toggleEvidence(String messageId) {
    setState(() {
      if (_expandedEvidence.contains(messageId)) {
        _expandedEvidence.remove(messageId);
      } else {
        _expandedEvidence.add(messageId);
      }
    });
  }

  Future<void> _openConversationPicker() async {
    final locale = ref.read(localeControllerProvider).locale;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(translate(locale, 'chat.conversation.manageTitle')),
                trailing: IconButton(
                  onPressed: _createConversation,
                  icon: const Icon(Icons.add),
                ),
              ),
              if (_isLoadingConversations)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                )
              else if (_conversations.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(translate(locale, 'chat.conversation.empty')),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _conversations.length,
                    itemBuilder: (context, index) {
                      final conversation = _conversations[index];
                      return ListTile(
                        title: Text(conversation.title ?? translate(locale, 'chat.conversation.defaultTitle')),
                        subtitle: Text(conversation.summary ?? translate(locale, 'chat.conversation.summaryEmpty')),
                        onTap: () {
                          Navigator.of(context).pop();
                          _switchConversation(conversation);
                        },
                        trailing: IconButton(
                          onPressed: () => _deleteConversation(conversation),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openKnowledgePicker() async {
    final locale = ref.read(localeControllerProvider).locale;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(translate(locale, 'chat.knowledge.select')),
                    trailing: TextButton(
                      onPressed: () {
                        setSheetState(() {
                          _selectedKnowledgeBaseIds = [];
                        });
                        setState(() {
                          _selectedKnowledgeBaseIds = [];
                        });
                        Navigator.of(context).pop();
                      },
                      child: Text(translate(locale, 'chat.knowledge.all')),
                    ),
                  ),
                  if (_isLoadingKnowledge)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    )
                  else if (_knowledgeBases.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(translate(locale, 'knowledge.empty')),
                    )
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: _knowledgeBases.map((kb) {
                          final selected = _selectedKnowledgeBaseIds.contains(kb.id);
                          return CheckboxListTile(
                            value: selected,
                            title: Text(kb.name),
                            subtitle: kb.description != null ? Text(kb.description!) : null,
                            onChanged: (checked) {
                              setSheetState(() {
                                if (checked == true) {
                                  _selectedKnowledgeBaseIds.add(kb.id);
                                } else {
                                  _selectedKnowledgeBaseIds.remove(kb.id);
                                }
                              });
                              setState(() {
                                _selectedKnowledgeBaseIds = _selectedKnowledgeBaseIds.toList();
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openModelPicker() async {
    final locale = ref.read(localeControllerProvider).locale;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(translate(locale, 'chat.model.select')),
              ),
              if (_chatModels.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(translate(locale, 'chat.model.empty')),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: _chatModels.map((model) {
                      final selected = model == _chatModel;
                      return ListTile(
                        title: Text(model),
                        trailing: selected ? const Icon(Icons.check) : null,
                        onTap: () async {
                          final storage = ref.read(storageServiceProvider);
                          await storage.setAiConfig(model: model);
                          await _loadModels();
                          if (!context.mounted) {
                            return;
                          }
                          Navigator.of(context).pop();
                        },
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportConversation() async {
    final locale = ref.read(localeControllerProvider).locale;
    if (_messages.isEmpty) {
      _showMessage(translate(locale, 'chat.export.none.message'));
      return;
    }
    final content = _buildExportText(_messages, _conversationId, locale);
    await Share.share(content, subject: translate(locale, 'chat.export.title'));
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _buildSummary(String value) {
    final trimmed = value.replaceAll(RegExp(r'\\s+'), ' ').trim();
    if (trimmed.length <= 50) {
      return trimmed;
    }
    return '${trimmed.substring(0, 50)}...';
  }

  String _buildExportText(List<Message> messages, String? conversationId, String locale) {
    final header = [
      translate(locale, 'chat.export.title'),
      translate(locale, 'chat.export.sessionId', {'id': conversationId ?? translate(locale, 'common.placeholder')}),
      translate(locale, 'chat.export.time', {'time': formatDateTime(DateTime.now().toIso8601String(), locale)}),
      '',
    ];
    final blocks = messages.map((message) {
      final roleLabel = switch (message.role) {
        MessageRole.user => translate(locale, 'chat.role.user'),
        MessageRole.assistant => translate(locale, 'chat.role.assistant'),
        MessageRole.system => translate(locale, 'chat.role.system'),
      };
      final timestamp = message.createdAt != null ? formatDateTime(message.createdAt, locale) : '';
      return '$roleLabel${timestamp.isNotEmpty ? ' ($timestamp)' : ''}:\\n${message.content}';
    }).toList();
    return [...header, ...blocks].join('\\n\\n');
  }

  String _ragStepTitle(String locale, RagVisualizationStep step) {
    switch (step) {
      case RagVisualizationStep.query:
        return translate(locale, 'rag.step.query');
      case RagVisualizationStep.embedding:
        return translate(locale, 'rag.step.embedding');
      case RagVisualizationStep.retrieval:
        return translate(locale, 'rag.step.retrieval');
      case RagVisualizationStep.prompt:
        return translate(locale, 'rag.step.prompt');
      case RagVisualizationStep.generating:
        return translate(locale, 'rag.step.generating');
      case RagVisualizationStep.completed:
        return translate(locale, 'rag.flow.title');
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeControllerProvider).locale;
    final palette = Theme.of(context).colorScheme;
    final modelLabel = _chatModel.isNotEmpty ? _chatModel : translate(locale, 'chat.model.missing');

    return Scaffold(
      appBar: AppBar(
        title: Text(translate(locale, 'chat.title')),
        actions: [
          IconButton(
            onPressed: _openConversationPicker,
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: translate(locale, 'chat.manage'),
          ),
          IconButton(
            onPressed: _openKnowledgePicker,
            icon: const Icon(Icons.library_books_outlined),
            tooltip: translate(locale, 'chat.knowledge.select'),
          ),
          IconButton(
            onPressed: _openModelPicker,
            icon: const Icon(Icons.smart_toy_outlined),
            tooltip: modelLabel,
          ),
          IconButton(
            onPressed: () => setState(() => _showVisualization = true),
            icon: const Icon(Icons.graphic_eq),
            tooltip: translate(locale, 'chat.flow'),
          ),
          IconButton(
            onPressed: _exportConversation,
            icon: const Icon(Icons.share),
            tooltip: translate(locale, 'chat.export'),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty
                        ? Center(
                            child: Text(
                              translate(locale, 'chat.welcome'),
                              style: TextStyle(color: palette.onSurface.withAlpha(153)),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[index];
                              return _MessageBubble(
                                message: message,
                                expanded: _expandedEvidence.contains(message.id),
                                onToggleEvidence: () => _toggleEvidence(message.id),
                                locale: locale,
                                isStreaming: message.id == _streamingMessageId,
                                ragStepTitle: _ragStepTitle(locale, _visualizationStep),
                              );
                            },
                          ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inputController,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: translate(locale, 'chat.input.placeholder'),
                          ),
                          onSubmitted: (_) => _handleSend(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: _isSending ? null : _handleSend,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_showVisualization)
            RagVisualization(
              data: _visualizationData,
              currentStep: _visualizationStep,
              locale: locale,
              onClose: () => setState(() => _showVisualization = false),
            ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.expanded,
    required this.onToggleEvidence,
    required this.locale,
    required this.isStreaming,
    required this.ragStepTitle,
  });

  final Message message;
  final bool expanded;
  final VoidCallback onToggleEvidence;
  final String locale;
  final bool isStreaming;
  final String ragStepTitle;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final palette = Theme.of(context).colorScheme;
    final assistantTint = Color.alphaBlend(palette.onSurface.withAlpha(13), palette.surface);
    final bubbleColor = isUser ? palette.primary : assistantTint;
    final textColor = isUser ? palette.onPrimary : palette.onSurface;
    final evidence = message.metadata?.evidence ?? [];
    final theme = Theme.of(context);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            message.role == MessageRole.system
                ? Text(message.content, style: TextStyle(color: textColor))
                : (isStreaming && message.content.isEmpty)
                    ? Text(
                        ragStepTitle,
                        style: TextStyle(color: textColor.withAlpha(179), fontStyle: FontStyle.italic),
                      )
                    : _AnimatedMarkdownText(
                        text: message.content,
                        animate: isStreaming,
                        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                          p: TextStyle(color: textColor, fontSize: 15, height: 1.4),
                          code: TextStyle(
                            color: textColor,
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: palette.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          blockquoteDecoration: BoxDecoration(
                            color: assistantTint,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
            if (evidence.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onToggleEvidence,
                style: TextButton.styleFrom(foregroundColor: textColor),
                child: Text(
                  expanded
                      ? translate(locale, 'chat.evidence.collapse')
                      : translate(locale, 'chat.evidence.expand'),
                ),
              ),
              if (expanded)
                ...evidence.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${item.documentTitle ?? translate(locale, 'context.untitled')} #${item.chunkIndex ?? ''}\\n${item.snippet}',
                      style: TextStyle(color: textColor, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnimatedMarkdownText extends StatefulWidget {
  const _AnimatedMarkdownText({
    required this.text,
    required this.animate,
    required this.styleSheet,
  });

  final String text;
  final bool animate;
  final MarkdownStyleSheet styleSheet;

  @override
  State<_AnimatedMarkdownText> createState() => _AnimatedMarkdownTextState();
}

class _AnimatedMarkdownTextState extends State<_AnimatedMarkdownText> {
  static const _tick = Duration(milliseconds: 20);

  Timer? _timer;
  List<String> _characters = const [];
  int _visibleCount = 0;

  @override
  void initState() {
    super.initState();
    _syncText(reset: true);
  }

  @override
  void didUpdateWidget(covariant _AnimatedMarkdownText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.animate != widget.animate) {
      final shouldReset = widget.text.length < oldWidget.text.length ||
          !widget.text.startsWith(oldWidget.text) ||
          !widget.animate;
      _syncText(reset: shouldReset);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncText({required bool reset}) {
    final chars = widget.text.characters.toList();
    _characters = chars;

    if (!widget.animate) {
      _visibleCount = chars.length;
      _timer?.cancel();
      setState(() {});
      return;
    }

    if (reset || _visibleCount > chars.length) {
      _visibleCount = 0;
    }

    if (_visibleCount < chars.length) {
      _startTimer();
    } else {
      _timer?.cancel();
      setState(() {});
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_visibleCount >= _characters.length) {
        timer.cancel();
        return;
      }
      setState(() {
        _visibleCount += 1;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleText = _characters.take(_visibleCount).join();
    return MarkdownBody(
      data: visibleText,
      extensionSet: md.ExtensionSet.gitHubWeb,
      softLineBreak: true,
      styleSheet: widget.styleSheet,
    );
  }
}
