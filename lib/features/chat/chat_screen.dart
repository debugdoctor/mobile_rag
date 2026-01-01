import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_providers.dart';
import '../../core/i18n.dart';
import '../../domain/models.dart';
import '../../services/api_service.dart';
import '../../services/rag_service.dart';
import '../../utils/attachment_extractor.dart';
import '../../utils/file_text_extractor.dart';
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
  List<PromptTemplate> _promptTemplates = [];
  String? _conversationId;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isProcessingAttachments = false;
  bool _isLoadingConversations = false;
  bool _isLoadingKnowledge = false;
  String _chatModel = '';
  List<String> _chatModels = [];
  List<String> _selectedKnowledgeBaseIds = [];
  final Set<String> _expandedEvidence = {};
  String? _streamingMessageId;
  CancelToken? _streamCancelToken;
  String? _pendingRetryContent;
  String? _pendingRetryConversationId;
  String? _pendingRetryAttachmentsContent;
  String? _pendingRetryPromptId;
  String? _lastErrorMessageId;
  bool _showRetryNotice = false;
  final List<_PendingAttachment> _pendingAttachments = [];
  List<FileUnderstandingAttachment> _pendingAttachmentPayloads = [];
  final Map<String, String> _attachmentSummaries = {};
  bool _knowledgeEnhancementEnabled = true;
  bool _showKnowledgeToast = false;
  Timer? _knowledgeToastTimer;
  StreamSubscription<StreamedMessageUpdate>? _streamUpdatesSubscription;

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
  String? _selectedPromptTemplateId;

  @override
  void initState() {
    super.initState();
    _streamUpdatesSubscription =
        ref.read(ragServiceProvider).streamingUpdates.listen(_handleStreamUpdate);
    _loadInitial();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _knowledgeToastTimer?.cancel();
    _streamUpdatesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    await Future.wait([
      _loadConversation(),
      _loadConversations(),
      _loadKnowledgeBases(),
      _loadPromptTemplates(),
      _loadModels(),
    ]);
    if (mounted) {
      _scrollToBottom();
    }
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

  Future<void> _loadPromptTemplates() async {
    final storage = ref.read(storageServiceProvider);
    final templates = await storage.getPromptTemplates();
    if (!mounted) {
      return;
    }
    setState(() {
      _promptTemplates = templates;
      if (_selectedPromptTemplateId == null ||
          !_promptTemplates.any((item) => item.id == _selectedPromptTemplateId)) {
        _selectedPromptTemplateId = defaultPromptTemplateId;
      }
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
        _pendingRetryContent = null;
        _pendingRetryConversationId = null;
        _pendingRetryPromptId = null;
        _lastErrorMessageId = null;
        _streamingMessageId = null;
      });
      return;
    }
    final history = await rag.listMessages(latest.id);
    final selection = await _loadPromptSelection(latest.id);
    if (!mounted) {
      return;
    }
    final activeMessage = rag.activeStreamingMessage(latest.id);
    setState(() {
      _conversationId = latest.id;
      _messages = _mergeActiveStreamingMessage(history, activeMessage);
      _isLoading = false;
      _pendingRetryContent = null;
      _pendingRetryConversationId = null;
      _pendingRetryPromptId = null;
      _lastErrorMessageId = null;
      _streamingMessageId = rag.activeStreamingMessageId(latest.id);
      _selectedPromptTemplateId = selection;
    });
    _scrollToBottom();
  }

  Future<void> _switchConversation(Conversation conversation) async {
    setState(() {
      _conversationId = conversation.id;
      _isLoading = true;
      _pendingRetryContent = null;
      _pendingRetryConversationId = null;
      _pendingRetryPromptId = null;
      _lastErrorMessageId = null;
      _streamingMessageId = null;
    });
    final rag = ref.read(ragServiceProvider);
    final history = await rag.listMessages(conversation.id);
    final selection = await _loadPromptSelection(conversation.id);
    if (!mounted) {
      return;
    }
    final activeMessage = rag.activeStreamingMessage(conversation.id);
    setState(() {
      _messages = _mergeActiveStreamingMessage(history, activeMessage);
      _isLoading = false;
      _streamingMessageId = rag.activeStreamingMessageId(conversation.id);
      _selectedPromptTemplateId = selection;
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
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
    if (text.isEmpty || _isSending || _isProcessingAttachments) {
      return;
    }
    final rag = ref.read(ragServiceProvider);
    setState(() {
      _isSending = true;
    });

    final attachmentsSummary = await _prepareAttachmentSummary(text);
    if (_pendingAttachments.isNotEmpty && attachmentsSummary == null) {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
      return;
    }

    var conversationId = _conversationId;
    if (conversationId == null) {
      final conversation = await rag.createConversation(text.substring(0, text.length > 40 ? 40 : text.length));
      conversationId = conversation.id;
      _conversationId = conversationId;
      await _loadConversations();
      _savePromptSelection(_selectedPromptTemplateId ?? defaultPromptTemplateId);
    }

    final userMessage = await rag.addMessage(conversationId, MessageRole.user, text);
    setState(() {
      _messages = [..._messages, userMessage];
      _inputController.clear();
    });
    if (mounted) {
      _scrollToBottom();
    }
    if (attachmentsSummary != null && attachmentsSummary.trim().isNotEmpty) {
      _attachmentSummaries[userMessage.id] = attachmentsSummary;
    }
    if (_pendingAttachments.isNotEmpty && attachmentsSummary != null) {
      setState(() {
        _pendingAttachments.clear();
        _pendingAttachmentPayloads = [];
      });
    }

    if (_messages.where((msg) => msg.role == MessageRole.user).length == 1) {
      await rag.updateConversation(
        conversationId,
        title: text.substring(0, text.length > 40 ? 40 : text.length),
        summary: _buildSummary(text),
        touch: false,
      );
      await _loadConversations();
    }

    final promptContent = _buildSystemPrompt(text);
    await _sendAssistantResponse(
      conversationId,
      text,
      attachmentsContent: attachmentsSummary,
      systemPromptContent: promptContent,
      promptTemplateId: _selectedPromptTemplateId,
    );
  }

  Future<void> _sendAssistantResponse(
    String conversationId,
    String text, {
    String? attachmentsContent,
    String? systemPromptContent,
    String? promptTemplateId,
  }) async {
    final rag = ref.read(ragServiceProvider);
    final locale = ref.read(localeControllerProvider).locale;
    Timer? chunkTimer;
    String? pendingContent;
    _streamCancelToken = CancelToken();
    _setStateIfMounted(() {
      _lastErrorMessageId = null;
    });

    final embeddingModel = _knowledgeEnhancementEnabled ? _resolveEmbeddingModel() : '';
    final knowledgeBaseIds =
        _knowledgeEnhancementEnabled ? (_selectedKnowledgeBaseIds.isEmpty ? null : _selectedKnowledgeBaseIds) : const <String>[];

    _setStateIfMounted(() {
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
          if (_streamingMessageId == null) {
            return;
          }
          pendingContent = chunk;
          if (chunkTimer != null) {
            return;
          }
          chunkTimer = Timer(const Duration(milliseconds: 120), () {
            chunkTimer = null;
            final content = pendingContent;
            if (content == null) {
              return;
            }
            _setStateIfMounted(() {
              final streamMessage = Message(
                id: _streamingMessageId!,
                role: MessageRole.assistant,
                content: content,
              );
              final index = _messages.indexWhere((msg) => msg.id == _streamingMessageId);
              if (index == -1) {
                _messages = [..._messages, streamMessage];
              } else {
                _messages = _messages.map((msg) => msg.id == _streamingMessageId ? streamMessage : msg).toList();
              }
            });
            if (mounted) {
              _scrollToBottom();
            }
          });
        },
        (step, data) {
          _setStateIfMounted(() {
            _visualizationStep = step;
            _visualizationData = data;
          });
        },
        knowledgeBaseIds: knowledgeBaseIds,
        embeddingModel: embeddingModel,
        cancelToken: _streamCancelToken,
        attachmentsContent: attachmentsContent,
        systemPromptContent: systemPromptContent,
        onStart: (message) {
          _setStateIfMounted(() {
            _messages = [..._messages, message];
            _streamingMessageId = message.id;
          });
          if (mounted) {
            _scrollToBottom();
          }
        },
      );
      _setStateIfMounted(() {
        _messages = _messages.map((msg) => msg.id == response.id ? response : msg).toList();
        _streamingMessageId = null;
        _pendingRetryContent = null;
        _pendingRetryConversationId = null;
        _pendingRetryAttachmentsContent = null;
        _pendingRetryPromptId = null;
        _showRetryNotice = false;
      });
    } catch (error) {
      chunkTimer?.cancel();
      if (_isCancelError(error)) {
        _setStateIfMounted(() {
          _streamingMessageId = null;
          _pendingRetryContent = null;
          _pendingRetryConversationId = null;
          _pendingRetryAttachmentsContent = null;
          _pendingRetryPromptId = null;
          _lastErrorMessageId = null;
          _showRetryNotice = false;
        });
        return;
      }
      final failedMessageId = _streamingMessageId;
      final friendlyError = _formatErrorMessage(error, locale);
      _setStateIfMounted(() {
        if (failedMessageId != null) {
          final index = _messages.indexWhere((msg) => msg.id == failedMessageId);
          final existing = index == -1 ? null : _messages[index];
          final hasContent = existing != null && existing.content.trim().isNotEmpty;
          if (!hasContent) {
            final systemMessage = Message(
              id: failedMessageId,
              role: MessageRole.system,
              content: friendlyError,
            );
            if (index == -1) {
              _messages = [..._messages, systemMessage];
            } else {
              _messages = _messages.map((msg) => msg.id == failedMessageId ? systemMessage : msg).toList();
            }
          }
          _lastErrorMessageId = hasContent ? null : failedMessageId;
        } else {
          _lastErrorMessageId = null;
        }
        _streamingMessageId = null;
        _pendingRetryContent = text;
        _pendingRetryConversationId = conversationId;
        _pendingRetryAttachmentsContent = attachmentsContent;
        _pendingRetryPromptId = promptTemplateId;
        _showRetryNotice = true;
      });
      _showMessage(friendlyError);
    } finally {
      chunkTimer?.cancel();
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
      _streamCancelToken = null;
    }
  }

  String? _resolveEmbeddingModel() {
    if (!_knowledgeEnhancementEnabled) {
      return null;
    }
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
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(translate(locale, 'chat.conversation.manageTitle')),
                    trailing: IconButton(
                      onPressed: () async {
                        await _createConversation();
                        if (!context.mounted) {
                          return;
                        }
                        setSheetState(() {});
                      },
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
                              onPressed: () async {
                                await _deleteConversation(conversation);
                                if (!context.mounted) {
                                  return;
                                }
                                setSheetState(() {});
                              },
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
      },
    );
  }

  void _toggleKnowledgeEnhancement() {
    final enabled = !_knowledgeEnhancementEnabled;
    setState(() {
      _knowledgeEnhancementEnabled = enabled;
      if (!enabled) {
        _showKnowledgeToast = false;
      }
    });
    if (enabled) {
      _showKnowledgeToastMessage();
    } else {
      _knowledgeToastTimer?.cancel();
    }
  }

  void _showKnowledgeToastMessage() {
    _knowledgeToastTimer?.cancel();
    setState(() {
      _showKnowledgeToast = true;
    });
    _knowledgeToastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showKnowledgeToast = false;
        });
      }
    });
  }

  String? _buildSystemPrompt(String question, {String? templateId}) {
    final id = templateId ?? _selectedPromptTemplateId ?? defaultPromptTemplateId;
    final template = _promptTemplates.firstWhere(
      (item) => item.id == id,
      orElse: () => PromptTemplate(id: '', title: '', content: ''),
    );
    final locale = ref.read(localeControllerProvider).locale;
    final content = template.id == defaultPromptTemplateId
        ? translate(locale, 'prompt.system')
        : template.content;
    if (content.trim().isEmpty) {
      return null;
    }
    final knowledge = _resolveKnowledgeLabel(locale);
    return content
        .replaceAll('{{question}}', question)
        .replaceAll('{{knowledge}}', knowledge)
        .replaceAll('{question}', question)
        .replaceAll('{knowledge}', knowledge);
  }

  String _promptTitle(String locale, PromptTemplate template) {
    if (template.id == defaultPromptTemplateId) {
      return translate(locale, 'settings.prompt.defaultTitle');
    }
    return template.title;
  }

  String _promptPreview(String locale, PromptTemplate template) {
    if (template.id == defaultPromptTemplateId) {
      return translate(locale, 'prompt.system');
    }
    return template.content;
  }

  String _resolveKnowledgeLabel(String locale) {
    if (!_knowledgeEnhancementEnabled) {
      return translate(locale, 'chat.knowledge.disabled');
    }
    final ids = _selectedKnowledgeBaseIds.isEmpty
        ? _knowledgeBases.map((kb) => kb.id).toList()
        : _selectedKnowledgeBaseIds;
    final names = _knowledgeBases.where((kb) => ids.contains(kb.id)).map((kb) => kb.name).toList();
    if (names.isEmpty) {
      return translate(locale, 'chat.knowledge.empty');
    }
    return names.join(', ');
  }

  Future<void> _retrySend() async {
    final content = _pendingRetryContent;
    final conversationId = _pendingRetryConversationId;
    final attachmentsContent = _pendingRetryAttachmentsContent;
    final promptId = _pendingRetryPromptId;
    if (content == null || conversationId == null || _isSending) {
      return;
    }
    setState(() {
      _isSending = true;
      if (_lastErrorMessageId != null) {
        _messages = _messages.where((msg) => msg.id != _lastErrorMessageId).toList();
      }
      _lastErrorMessageId = null;
      _pendingRetryContent = null;
      _pendingRetryConversationId = null;
      _pendingRetryAttachmentsContent = null;
      _pendingRetryPromptId = null;
      _showRetryNotice = false;
    });
    final promptContent = _buildSystemPrompt(content, templateId: promptId);
    await _sendAssistantResponse(
      conversationId,
      content,
      attachmentsContent: attachmentsContent,
      systemPromptContent: promptContent,
      promptTemplateId: promptId,
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

  Future<void> _openPromptPicker() async {
    final locale = ref.read(localeControllerProvider).locale;
    await _loadPromptTemplates();
    if (!context.mounted) {
      return;
    }
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
                    title: Text(translate(locale, 'chat.prompt.select')),
                    trailing: TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedPromptTemplateId = defaultPromptTemplateId;
                        });
                        _savePromptSelection(defaultPromptTemplateId);
                        setSheetState(() {});
                      },
                      child: Text(translate(locale, 'chat.prompt.clear')),
                    ),
                  ),
                  if (_promptTemplates.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(translate(locale, 'chat.prompt.empty')),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _promptTemplates.length,
                        itemBuilder: (context, index) {
                          final template = _promptTemplates[index];
                          final selected = _selectedPromptTemplateId == template.id;
                          return ListTile(
                            title: Text(_promptTitle(locale, template)),
                            subtitle: Text(
                              _promptPreview(locale, template),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            leading: Icon(
                              selected ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: selected ? Theme.of(context).colorScheme.primary : null,
                            ),
                            onTap: () {
                              setState(() {
                                _selectedPromptTemplateId = template.id;
                              });
                              _savePromptSelection(template.id);
                              setSheetState(() {});
                              Navigator.of(context).pop();
                            },
                          );
                        },
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

  Future<String> _loadPromptSelection(String conversationId) async {
    final storage = ref.read(storageServiceProvider);
    final selections = await storage.getPromptSelections();
    return selections[conversationId] ?? defaultPromptTemplateId;
  }

  void _savePromptSelection(String promptId) {
    final conversationId = _conversationId;
    if (conversationId == null) {
      return;
    }
    ref.read(storageServiceProvider).setPromptSelection(conversationId, promptId);
  }

  Future<void> _exportConversation() async {
    final locale = ref.read(localeControllerProvider).locale;
    if (_messages.isEmpty) {
      _showMessage(translate(locale, 'chat.export.none.message'));
      return;
    }
    final content = _buildExportMarkdown(_messages, _conversationId, locale);
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final sessionId = _conversationId ?? 'session';
    final file = File('${dir.path}/conversation_${sessionId}_$timestamp.md');
    await file.writeAsString(content);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/markdown')],
      subject: translate(locale, 'chat.export.title'),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatErrorMessage(Object error, String locale) {
    if (error is StateError) {
      return error.message;
    }
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionError) {
        return translate(locale, 'error.networkUnavailable');
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return translate(locale, 'error.requestTimeout');
      }
      if (error.type == DioExceptionType.badResponse) {
        final status = error.response?.statusCode;
        if (status != null) {
          return translate(locale, 'error.requestFailed', {'status': status});
        }
      }
      final inner = error.error;
      if (inner is SocketException) {
        return translate(locale, 'error.networkUnavailable');
      }
      if (inner is FormatException) {
        return translate(locale, 'error.invalidUrl');
      }
    }
    if (error is SocketException) {
      return translate(locale, 'error.networkUnavailable');
    }
    if (error is FormatException) {
      return translate(locale, 'error.invalidUrl');
    }
    return translate(locale, 'error.unknown');
  }

  Future<void> _pickAttachments() async {
    final locale = ref.read(localeControllerProvider).locale;
    final ragConfig = await ref.read(storageServiceProvider).getRagConfig();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: attachmentSupportedExtensions.toList(),
      withData: true,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final next = List<_PendingAttachment>.from(_pendingAttachments);
    for (final file in result.files) {
      final name = file.name;
      if (!isSupportedAttachment(name)) {
        _showMessage(translate(locale, 'chat.attach.unsupported'));
        continue;
      }
      if (ragConfig.maxFileSizeMb > 0 && file.size > ragConfig.maxFileSizeMb * 1024 * 1024) {
        _showMessage(translate(locale, 'file.tooLarge', {'size': ragConfig.maxFileSizeMb}));
        continue;
      }
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final isImage = isImageAttachment(name);
      next.add(
        _PendingAttachment(
          name: name,
          bytes: bytes,
          isImage: isImage,
          mimeType: isImage ? guessAttachmentMime(name) : null,
        ),
      );
    }
    if (mounted) {
      setState(() {
        _pendingAttachments
          ..clear()
          ..addAll(next);
      });
    }
    await _preprocessAttachments();
  }

  void _removeAttachment(_PendingAttachment attachment) {
    setState(() {
      _pendingAttachments.remove(attachment);
    });
    _preprocessAttachments();
  }

  Future<void> _preprocessAttachments() async {
    if (_pendingAttachments.isEmpty) {
      if (mounted) {
        setState(() {
          _pendingAttachmentPayloads = [];
          _isProcessingAttachments = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _isProcessingAttachments = true;
      });
    }
    try {
      final payloads = await _buildAttachmentPayloads();
      if (mounted) {
        setState(() {
          _pendingAttachmentPayloads = payloads;
        });
      }
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingAttachments = false;
        });
      }
    }
  }

  Future<String?> _prepareAttachmentSummary(String question) async {
    if (_pendingAttachments.isEmpty) {
      return null;
    }
    final locale = ref.read(localeControllerProvider).locale;
    setState(() {
      _isProcessingAttachments = true;
    });
    try {
      final storage = ref.read(storageServiceProvider);
      final config = await storage.getAiConfig();
      final model = config.model;
      final api = ref.read(apiServiceProvider);
      final payloads =
          _pendingAttachmentPayloads.isNotEmpty ? _pendingAttachmentPayloads : await _buildAttachmentPayloads();
      if (payloads.isEmpty) {
        return '';
      }
      final prompt = translate(locale, 'chat.attach.prompt', {'question': question});
      final summary = await api.requestFileUnderstanding(
        prompt: prompt,
        attachments: payloads,
        model: model,
      );
      return summary.trim();
    } catch (error) {
      _showMessage(error.toString());
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingAttachments = false;
        });
      }
    }
  }

  Future<List<FileUnderstandingAttachment>> _buildAttachmentPayloads() async {
    const maxTextLength = 12000;
    final payloads = <FileUnderstandingAttachment>[];
    for (final attachment in _pendingAttachments) {
      if (attachment.isImage) {
        final base64Data = base64Encode(attachment.bytes);
        payloads.add(
          FileUnderstandingAttachment(
            name: attachment.name,
            mimeType: attachment.mimeType ?? guessAttachmentMime(attachment.name),
            base64Data: base64Data,
          ),
        );
        continue;
      }
      try {
        final text = isPdfAttachment(attachment.name)
            ? await compute(extractTextFromFileBytesIsolate, {
                'filename': attachment.name,
                'bytes': attachment.bytes,
              })
            : utf8.decode(attachment.bytes, allowMalformed: true);
        final trimmed = text.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        final limited = trimmed.length > maxTextLength ? trimmed.substring(0, maxTextLength) : trimmed;
        payloads.add(FileUnderstandingAttachment(name: attachment.name, text: limited));
      } catch (error) {
        _showMessage('$error');
      }
    }
    return payloads;
  }

  String? _latestAssistantMessageId() {
    for (var i = _messages.length - 1; i >= 0; i -= 1) {
      if (_messages[i].role == MessageRole.assistant) {
        return _messages[i].id;
      }
    }
    return null;
  }

  Future<void> _copyMessage(Message message) async {
    if (message.content.trim().isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: message.content));
    final locale = ref.read(localeControllerProvider).locale;
    _showMessage(translate(locale, 'chat.action.copied'));
  }

  Future<void> _regenerateMessage(Message message) async {
    if (_streamingMessageId != null || _isSending) {
      return;
    }
    if (message.role != MessageRole.assistant) {
      return;
    }
    final latestAssistantId = _latestAssistantMessageId();
    if (latestAssistantId == null || message.id != latestAssistantId) {
      return;
    }
    final index = _messages.indexWhere((item) => item.id == message.id);
    if (index <= 0) {
      return;
    }
    String? userContent;
    String? userMessageId;
    for (var i = index - 1; i >= 0; i -= 1) {
      if (_messages[i].role == MessageRole.user) {
        userContent = _messages[i].content;
        userMessageId = _messages[i].id;
        break;
      }
    }
    final conversationId = _conversationId;
    if (userContent == null || conversationId == null || userContent.trim().isEmpty) {
      return;
    }
    setState(() {
      _messages = _messages.where((item) => item.id != message.id).toList();
    });
    try {
      await ref.read(ragServiceProvider).deleteMessage(message.id);
    } catch (error) {
      _showMessage(error.toString());
    }
    final attachmentsContent = userMessageId != null ? _attachmentSummaries[userMessageId] : null;
    final promptContent = _buildSystemPrompt(userContent);
    _sendAssistantResponse(
      conversationId,
      userContent,
      attachmentsContent: attachmentsContent,
      systemPromptContent: promptContent,
      promptTemplateId: _selectedPromptTemplateId,
    );
  }

  bool _isCancelError(Object error) {
    return error is DioException && error.type == DioExceptionType.cancel;
  }

  void _stopStreaming() {
    if (_streamCancelToken == null || _streamCancelToken!.isCancelled) {
      return;
    }
    _streamCancelToken?.cancel('user_stop');
    _setStateIfMounted(() {
      _streamingMessageId = null;
      _isSending = false;
      _pendingRetryContent = null;
      _pendingRetryConversationId = null;
      _lastErrorMessageId = null;
    });
  }

  void _setStateIfMounted(VoidCallback action) {
    if (!mounted) {
      return;
    }
    setState(action);
  }

  void _handleStreamUpdate(StreamedMessageUpdate update) {
    if (update.conversationId != _conversationId) {
      return;
    }
    _setStateIfMounted(() {
      if (update.isDeleted) {
        _messages = _messages.where((item) => item.id != update.messageId).toList();
      } else if (update.message != null) {
        final index = _messages.indexWhere((item) => item.id == update.messageId);
        if (index == -1) {
          _messages = [..._messages, update.message!];
        } else {
          final existing = _messages[index];
          final incoming = update.message!;
          final next = incoming.content.length >= existing.content.length ? incoming : existing;
          _messages = _messages.map((item) => item.id == update.messageId ? next : item).toList();
        }
      }
      _streamingMessageId = update.isDone ? null : update.messageId;
    });
    if (mounted) {
      _scrollToBottom();
    }
  }

  List<Message> _mergeActiveStreamingMessage(List<Message> history, Message? activeMessage) {
    if (activeMessage == null) {
      return history;
    }
    final index = history.indexWhere((item) => item.id == activeMessage.id);
    if (index == -1) {
      return [...history, activeMessage];
    }
    return history.map((item) {
      if (item.id != activeMessage.id) {
        return item;
      }
      return activeMessage.content.length >= item.content.length ? activeMessage : item;
    }).toList();
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

  String _buildExportMarkdown(List<Message> messages, String? conversationId, String locale) {
    final header = [
      '# ${translate(locale, 'chat.export.title')}',
      '- ${translate(locale, 'chat.export.sessionId', {'id': conversationId ?? translate(locale, 'common.placeholder')})}',
      '- ${translate(locale, 'chat.export.time', {'time': formatDateTime(DateTime.now().toIso8601String(), locale)})}',
      '',
    ];
    final blocks = messages.map((message) {
      final roleLabel = switch (message.role) {
        MessageRole.user => translate(locale, 'chat.role.user'),
        MessageRole.assistant => translate(locale, 'chat.role.assistant'),
        MessageRole.system => translate(locale, 'chat.role.system'),
      };
      final timestamp = message.createdAt != null ? formatDateTime(message.createdAt, locale) : '';
      final parts = <String>[
        '## $roleLabel${timestamp.isNotEmpty ? ' ($timestamp)' : ''}',
        message.content,
      ];
      final evidence = message.metadata?.evidence ?? [];
      if (evidence.isNotEmpty) {
        parts.add('');
        parts.add('**${translate(locale, 'chat.evidence.title')}**');
        for (final item in evidence) {
          final title = item.documentTitle ?? translate(locale, 'context.untitled');
          final index = item.chunkIndex != null ? '#${item.chunkIndex}' : '';
          final hitRateText = item.hitRate != null
              ? translate(locale, 'chat.evidence.hitRate',
                  {'value': (item.hitRate! * 100).toStringAsFixed(0)})
              : null;
          final similarityText = item.similarity != null
              ? translate(locale, 'chat.evidence.similarity',
                  {'value': (item.similarity! * 100).toStringAsFixed(0)})
              : null;
          final stats = [
            if (hitRateText != null) hitRateText,
            if (similarityText != null) similarityText,
          ];
          parts.add('- $title ${index.isNotEmpty ? index : ''}${stats.isNotEmpty ? ' · ${stats.join(' · ')}' : ''}'.trim());
          final snippet = item.snippet.trim();
          if (snippet.isNotEmpty) {
            parts.add('  > ${snippet.replaceAll('\\n', '\\n  > ')}');
          }
        }
      }
      return parts.join('\\n');
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
    final knowledgeColor = _knowledgeEnhancementEnabled ? palette.primary : palette.onSurface;
    final selectedPrompt = _promptTemplates.firstWhere(
      (item) => item.id == _selectedPromptTemplateId,
      orElse: () => PromptTemplate(id: '', title: '', content: ''),
    );
    final promptLabel = translate(locale, 'chat.prompt.placeholder');

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
          if (_pendingRetryContent != null && !_showRetryNotice)
            IconButton(
              onPressed: _retrySend,
              icon: const Icon(Icons.refresh),
              tooltip: translate(locale, 'common.retry'),
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
          if (_showRetryNotice && _pendingRetryContent != null)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  setState(() {
                    _showRetryNotice = false;
                  });
                },
              ),
            ),
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
                              final latestAssistantId = _latestAssistantMessageId();
                              return _MessageBubble(
                                message: message,
                                expanded: _expandedEvidence.contains(message.id),
                                onToggleEvidence: () => _toggleEvidence(message.id),
                                onCopy: () => _copyMessage(message),
                                onRegenerate: () => _regenerateMessage(message),
                                isLatestAssistant: message.id == latestAssistantId,
                                canRegenerate: _streamingMessageId == null && !_isSending,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          OutlinedButton(
                            onPressed: _toggleKnowledgeEnhancement,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: knowledgeColor, width: 1.2),
                              foregroundColor: knowledgeColor,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            child: Text(translate(locale, 'chat.knowledge.toggle')),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _openPromptPicker,
                            icon: const Icon(Icons.bolt, size: 18),
                            label: Text(promptLabel),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_pendingAttachments.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: _pendingAttachments
                              .map(
                                (attachment) => Chip(
                                  label: Text(attachment.name, overflow: TextOverflow.ellipsis),
                                  onDeleted: () => _removeAttachment(attachment),
                                ),
                              )
                              .toList(),
                        ),
                      if (_pendingAttachments.isNotEmpty) const SizedBox(height: 8),
                      if (_isProcessingAttachments)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            translate(locale, 'chat.attach.processing'),
                            style: TextStyle(color: palette.onSurface.withAlpha(153), fontSize: 12),
                          ),
                        ),
                      Row(
                        children: [
                          IconButton(
                            onPressed: _isSending || _isProcessingAttachments ? null : _pickAttachments,
                            icon: const Icon(Icons.attach_file),
                            tooltip: translate(locale, 'chat.attach.add'),
                          ),
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
                            onPressed: _streamingMessageId != null
                                ? _stopStreaming
                                : (_isSending || _isProcessingAttachments ? null : _handleSend),
                            icon: Icon(_streamingMessageId != null ? Icons.stop_circle : Icons.send),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_showRetryNotice && _pendingRetryContent != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 80,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: palette.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: palette.outline),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(translate(locale, 'chat.retry.cached'))),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _retrySend,
                        child: Text(translate(locale, 'common.retry')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            left: 16,
            right: 16,
            bottom: _showKnowledgeToast ? 120 : 110,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _showKnowledgeToast ? 1 : 0,
              child: IgnorePointer(
                ignoring: true,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: palette.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(30),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(translate(locale, 'chat.knowledge.enabledToast')),
                  ),
                ),
              ),
            ),
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
    required this.onCopy,
    required this.onRegenerate,
    required this.isLatestAssistant,
    required this.canRegenerate,
    required this.locale,
    required this.isStreaming,
    required this.ragStepTitle,
  });

  final Message message;
  final bool expanded;
  final VoidCallback onToggleEvidence;
  final VoidCallback onCopy;
  final VoidCallback onRegenerate;
  final bool isLatestAssistant;
  final bool canRegenerate;
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
    final showFooter = message.role == MessageRole.assistant && message.content.trim().isNotEmpty;

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
            if (evidence.isNotEmpty && !isStreaming) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onToggleEvidence,
                style: TextButton.styleFrom(
                  foregroundColor: textColor,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                ),
                child: Text(
                  expanded
                      ? translate(locale, 'chat.evidence.collapse')
                      : translate(locale, 'chat.evidence.expand'),
                ),
              ),
              if (expanded)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isUser ? palette.onPrimary.withAlpha(20) : palette.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: palette.outline.withAlpha(60)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        translate(locale, 'chat.evidence.title'),
                        style: TextStyle(
                          color: textColor.withAlpha(200),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...evidence.map((item) {
                        final title = item.documentTitle ?? translate(locale, 'context.untitled');
                        final index = item.chunkIndex != null ? '#${item.chunkIndex}' : '';
                        final hitRateText = item.hitRate != null
                            ? translate(locale, 'chat.evidence.hitRate',
                                {'value': (item.hitRate! * 100).toStringAsFixed(0)})
                            : null;
                        final similarityText = item.similarity != null
                            ? translate(locale, 'chat.evidence.similarity',
                                {'value': (item.similarity! * 100).toStringAsFixed(0)})
                            : null;
                        final stats = [
                          if (hitRateText != null) hitRateText,
                          if (similarityText != null) similarityText,
                        ];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$title ${index.isNotEmpty ? index : ''}'.trim(),
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (stats.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2, bottom: 4),
                                  child: Text(
                                    stats.join(' · '),
                                    style: TextStyle(
                                      color: textColor.withAlpha(180),
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              Text(
                                item.snippet,
                                style: TextStyle(color: textColor.withAlpha(210), fontSize: 12, height: 1.35),
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
            ],
            if (showFooter) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: onCopy,
                    style: TextButton.styleFrom(
                      foregroundColor: textColor.withAlpha(204),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                    ),
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text(translate(locale, 'chat.action.copy')),
                  ),
                  const SizedBox(width: 8),
                  if (isLatestAssistant)
                    TextButton.icon(
                      onPressed: canRegenerate ? onRegenerate : null,
                      style: TextButton.styleFrom(
                        foregroundColor: textColor.withAlpha(204),
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                      ),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(translate(locale, 'chat.action.regenerate')),
                    ),
                ],
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

class _PendingAttachment {
  _PendingAttachment({
    required this.name,
    required this.bytes,
    required this.isImage,
    this.mimeType,
  });

  final String name;
  final Uint8List bytes;
  final bool isImage;
  final String? mimeType;
}
