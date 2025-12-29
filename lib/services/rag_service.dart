import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../core/i18n.dart';
import '../domain/models.dart';
import '../utils/chunking.dart';
import 'api_service.dart';
import 'db_service.dart';
import 'storage_service.dart';

const _contextLimit = 6;
const _candidateLimit = 12;
const _evidenceLimit = 4;
const _embeddingBatchSize = 16;
const _embeddingCandidateMultiplier = 4;
const _streamUpdateInterval = Duration(milliseconds: 250);

class EmbeddingProgress {
  EmbeddingProgress({
    required this.stage,
    this.current,
    this.total,
    this.fileCurrent,
    this.fileTotal,
  });

  final String stage;
  final int? current;
  final int? total;
  final int? fileCurrent;
  final int? fileTotal;
}

class StreamedMessageUpdate {
  StreamedMessageUpdate({
    required this.conversationId,
    required this.messageId,
    this.message,
    this.isDone = false,
    this.isDeleted = false,
  });

  final String conversationId;
  final String messageId;
  final Message? message;
  final bool isDone;
  final bool isDeleted;
}

class RagVisualizationData {
  RagVisualizationData({
    required this.query,
    required this.candidates,
    required this.selectedEvidence,
    required this.context,
    required this.prompt,
    required this.answer,
    required this.embedding,
  });

  String query;
  List<RagVisualizationCandidate> candidates;
  List<Evidence> selectedEvidence;
  String context;
  String prompt;
  String answer;
  RagVisualizationEmbedding embedding;
}

class RagVisualizationCandidate {
  RagVisualizationCandidate({
    required this.id,
    this.documentTitle,
    this.chunkIndex,
    required this.content,
    this.score,
    this.similarity,
    this.hitRate,
  });

  final String id;
  final String? documentTitle;
  final int? chunkIndex;
  final String content;
  final double? score;
  final double? similarity;
  final double? hitRate;
}

class RagVisualizationEmbedding {
  RagVisualizationEmbedding({required this.enabled, this.model});

  final bool enabled;
  final String? model;
}

enum RagVisualizationStep { query, embedding, retrieval, prompt, generating, completed }

class RagService {
  RagService({
    required DbService db,
    required StorageService storage,
    required ApiService api,
  })  : _db = db,
        _storage = storage,
        _api = api;

  final DbService _db;
  final StorageService _storage;
  final ApiService _api;
  final StreamController<StreamedMessageUpdate> _streamUpdates = StreamController.broadcast();
  final Map<String, String> _activeStreamMessageIds = {};
  final Map<String, Message> _activeStreamMessages = {};

  Stream<StreamedMessageUpdate> get streamingUpdates => _streamUpdates.stream;

  String? activeStreamingMessageId(String conversationId) => _activeStreamMessageIds[conversationId];

  Message? activeStreamingMessage(String conversationId) => _activeStreamMessages[conversationId];

  Future<List<KnowledgeBase>> listKnowledgeBases() async {
    return _db.listKnowledgeBases();
  }

  Future<KnowledgeBase?> getKnowledgeBase(String id) async {
    return _db.getKnowledgeBase(id);
  }

  Future<KnowledgeBase> createKnowledgeBase(String name, {String? description}) async {
    final embeddingConfig = await _storage.getEmbeddingConfig();
    final ragConfig = await _storage.getRagConfig();
    final chunkSizeMin = getDefaultChunkMinSize(ragConfig.chunkSize);
    return _db.createKnowledgeBase(
      name: name,
      description: description,
      embeddingModel: embeddingConfig.model.isEmpty ? null : embeddingConfig.model,
      chunkSizeMin: chunkSizeMin,
      chunkSizeMax: ragConfig.chunkSize,
      chunkOverlap: ragConfig.chunkOverlap,
      maxFileSizeMb: ragConfig.maxFileSizeMb,
    );
  }

  Future<KnowledgeBase?> updateKnowledgeBase(
    String id, {
    String? name,
    String? description,
    String? embeddingModel,
    String? chunkSeparators,
    int? chunkSizeMin,
    int? chunkSizeMax,
    int? chunkOverlap,
    int? maxFileSizeMb,
  }) async {
    return _db.updateKnowledgeBase(
      id,
      name: name,
      description: description,
      embeddingModel: embeddingModel,
      chunkSeparators: chunkSeparators,
      chunkSizeMin: chunkSizeMin,
      chunkSizeMax: chunkSizeMax,
      chunkOverlap: chunkOverlap,
      maxFileSizeMb: maxFileSizeMb,
    );
  }

  Future<void> deleteKnowledgeBase(String id) async {
    return _db.deleteKnowledgeBase(id);
  }

  Future<void> deleteMessage(String messageId) async {
    return _db.deleteMessage(messageId);
  }

  Future<void> clearKnowledgeBaseDocuments(String knowledgeBaseId) async {
    return _db.clearKnowledgeBaseDocuments(knowledgeBaseId);
  }

  Future<void> clearAllDocuments() async {
    return _db.clearAllDocuments();
  }

  Future<List<Document>> listDocuments(String knowledgeBaseId) async {
    return _db.listDocuments(knowledgeBaseId);
  }

  Future<Document?> getDocument(String documentId) async {
    return _db.getDocument(documentId);
  }

  Future<Document> createDocument({
    required String knowledgeBaseId,
    required String title,
    required String content,
    int? chunkSizeMin,
    required int chunkSizeMax,
    required int chunkOverlap,
    String? embeddingModel,
    List<String>? chunkSeparators,
    void Function(EmbeddingProgress progress)? onProgress,
  }) async {
    final result = await _buildChunkEmbeddings(
      content: content,
      chunkSizeMin: chunkSizeMin,
      chunkSizeMax: chunkSizeMax,
      chunkOverlap: chunkOverlap,
      onProgress: onProgress,
      embeddingModel: embeddingModel,
      chunkSeparators: chunkSeparators,
    );
    final chunkCount = result.chunks.length;
    onProgress?.call(EmbeddingProgress(stage: 'saving', current: chunkCount, total: chunkCount));
    return _db.createDocument(
      knowledgeBaseId: knowledgeBaseId,
      title: title,
      content: content,
      chunkSizeMin: chunkSizeMin,
      chunkSizeMax: chunkSizeMax,
      chunkOverlap: chunkOverlap,
      chunks: result.chunks,
      embeddings: result.embeddings,
    );
  }

  Future<Document?> updateDocument({
    required String documentId,
    String? title,
    String? content,
    int? chunkSizeMin,
    int? chunkSizeMax,
    int? chunkOverlap,
    String? embeddingModel,
    List<String>? chunkSeparators,
    void Function(EmbeddingProgress progress)? onProgress,
  }) async {
    if (content != null) {
      final resolvedChunkSizeMax = chunkSizeMax ?? defaultRagConfig.chunkSize;
      final resolvedChunkSizeMin = chunkSizeMin ?? getDefaultChunkMinSize(resolvedChunkSizeMax);
      final resolvedChunkOverlap = chunkOverlap ?? defaultRagConfig.chunkOverlap;
      final result = await _buildChunkEmbeddings(
        content: content,
        chunkSizeMin: resolvedChunkSizeMin,
        chunkSizeMax: resolvedChunkSizeMax,
        chunkOverlap: resolvedChunkOverlap,
        onProgress: onProgress,
        embeddingModel: embeddingModel,
        chunkSeparators: chunkSeparators,
      );
      final chunkCount = result.chunks.length;
      onProgress?.call(EmbeddingProgress(stage: 'saving', current: chunkCount, total: chunkCount));
      return _db.updateDocument(
        documentId: documentId,
        title: title,
        content: content,
        chunkSizeMin: resolvedChunkSizeMin,
        chunkSizeMax: resolvedChunkSizeMax,
        chunkOverlap: resolvedChunkOverlap,
        chunks: result.chunks,
        embeddings: result.embeddings,
      );
    }
    return _db.updateDocument(
      documentId: documentId,
      title: title,
      content: content,
    );
  }

  Future<void> deleteDocument(String documentId) async {
    return _db.deleteDocument(documentId);
  }

  Future<List<DocumentChunk>> listDocumentChunks(String documentId) async {
    return _db.listDocumentChunks(documentId);
  }

  Future<void> rebuildDocumentChunks({
    required String documentId,
    required String content,
    int? chunkSizeMin,
    required int chunkSizeMax,
    required int chunkOverlap,
    String? embeddingModel,
    List<String>? chunkSeparators,
    void Function(EmbeddingProgress progress)? onProgress,
  }) async {
    final result = await _buildChunkEmbeddings(
      content: content,
      chunkSizeMin: chunkSizeMin,
      chunkSizeMax: chunkSizeMax,
      chunkOverlap: chunkOverlap,
      onProgress: onProgress,
      embeddingModel: embeddingModel,
      chunkSeparators: chunkSeparators,
    );
    final chunkCount = result.chunks.length;
    onProgress?.call(EmbeddingProgress(stage: 'saving', current: chunkCount, total: chunkCount));
    await _db.rebuildDocumentChunks(
      documentId: documentId,
      content: content,
      chunkSizeMin: chunkSizeMin,
      chunkSizeMax: chunkSizeMax,
      chunkOverlap: chunkOverlap,
      chunks: result.chunks,
      embeddings: result.embeddings,
      separators: chunkSeparators,
    );
  }

  Future<void> rebuildKnowledgeBaseChunks({
    required String knowledgeBaseId,
    String? embeddingModel,
    List<String>? chunkSeparators,
    int? chunkSizeMin,
    int? chunkSizeMax,
    int? chunkOverlap,
    void Function(EmbeddingProgress progress)? onProgress,
  }) async {
    final kb = await _db.getKnowledgeBase(knowledgeBaseId);
    final defaults = await _storage.getRagConfig();
    final resolvedChunkSizeMax = chunkSizeMax ?? kb?.chunkSizeMax ?? defaults.chunkSize;
    final resolvedChunkSizeMin =
        chunkSizeMin ?? kb?.chunkSizeMin ?? getDefaultChunkMinSize(resolvedChunkSizeMax);
    final resolvedChunkOverlap = chunkOverlap ?? kb?.chunkOverlap ?? defaults.chunkOverlap;
    final resolvedEmbeddingModel =
        embeddingModel ?? kb?.embeddingModel ?? (await _storage.getEmbeddingConfig()).model;
    final resolvedSeparators = chunkSeparators ?? parseChunkSeparators(kb?.chunkSeparators);

    final docs = await _db.listDocuments(knowledgeBaseId);
    for (final doc in docs) {
      final fullDoc = await _db.getDocument(doc.id);
      if (fullDoc?.content == null) {
        continue;
      }
      await rebuildDocumentChunks(
        documentId: doc.id,
        content: fullDoc!.content ?? '',
        chunkSizeMin: resolvedChunkSizeMin,
        chunkSizeMax: resolvedChunkSizeMax,
        chunkOverlap: resolvedChunkOverlap,
        embeddingModel: resolvedEmbeddingModel,
        chunkSeparators: resolvedSeparators,
        onProgress: onProgress,
      );
    }
  }

  Future<List<Conversation>> listConversations() async {
    return _db.listConversations();
  }

  Future<Conversation?> getLatestConversation() async {
    return _db.getLatestConversation();
  }

  Future<Conversation> createConversation([String? title]) async {
    return _db.createConversation(title);
  }

  Future<Conversation?> updateConversation(
    String id, {
    String? title,
    String? summary,
    bool touch = true,
  }) async {
    return _db.updateConversation(id, title: title, summary: summary, touch: touch);
  }

  Future<void> deleteConversation(String id) async {
    return _db.deleteConversation(id);
  }

  Future<List<Message>> listMessages(String conversationId) async {
    return _db.listMessages(conversationId);
  }

  Future<Message> addMessage(
    String conversationId,
    MessageRole role,
    String content, {
    MessageMetadata? metadata,
  }) async {
    return _db.addMessage(conversationId, role, content, metadata: metadata);
  }

  Future<Message> sendMessage(
    String conversationId,
    String content, {
    List<String>? knowledgeBaseIds,
    String? embeddingModel,
    String? attachmentsContent,
    String? systemPromptContent,
  }) async {
    final history = await _db.listMessages(conversationId);
    final locale = await _storage.getLocale();
    final config = await _storage.getRagConfig();
    final candidateLimit = _resolveCandidateLimit(config);
    final retrievalMode = config.retrievalMode;
    final queryText = _mergeQuery(content, attachmentsContent);
    final queryEmbedding = await _resolveQueryEmbedding(queryText, retrievalMode, embeddingModel);
    final disableKnowledge = knowledgeBaseIds != null && knowledgeBaseIds.isEmpty;

    final candidates = disableKnowledge
        ? <ChunkRow>[]
        : retrievalMode == 'document'
            ? <ChunkRow>[]
            : queryEmbedding != null
                ? await _db.listDocumentChunksForKnowledgeBases(knowledgeBaseIds: knowledgeBaseIds)
                : await _db.searchDocumentChunks(queryText, candidateLimit, knowledgeBaseIds: knowledgeBaseIds);

    final rankedChunks =
        retrievalMode == 'document' ? <RankedChunk>[] : _rankChunks(queryText, candidates, queryEmbedding);
    final filteredChunks = _applyChunkSimilarityThreshold(rankedChunks, config.retrievalSimilarityThreshold);
    final topChunks = filteredChunks.take(_contextLimit).toList();
    final evidenceItems = filteredChunks.take(_evidenceLimit).map((chunk) => chunk.evidence).toList();

    var context = '';
    var evidence = <Evidence>[];

    if (topChunks.isNotEmpty) {
      context = _buildChunkContext(topChunks, locale);
      evidence = evidenceItems;
    } else if (retrievalMode != 'chunk' && !disableKnowledge) {
      final docCandidates = await _db.searchDocuments(queryText, candidateLimit, knowledgeBaseIds: knowledgeBaseIds);
      final rankedDocs = _rankDocuments(queryText, docCandidates);
      final filteredDocs = _applyDocumentSimilarityThreshold(rankedDocs, config.retrievalSimilarityThreshold);
      final topDocs = filteredDocs.take(_contextLimit).toList();
      context = _buildContext(topDocs, locale);
      evidence = filteredDocs.take(_evidenceLimit).map((doc) => doc.evidence).toList();
    }

    final messages = _buildMessages(
      history,
      content,
      context,
      locale,
      attachmentsContent: attachmentsContent,
      systemPromptContent: systemPromptContent,
    );
    final answer = await _api.requestAiAnswer(AiRequestOptions(messages: messages));
    final metadata = evidence.isNotEmpty ? MessageMetadata(query: content, evidence: evidence) : null;
    return _db.addMessage(conversationId, MessageRole.assistant, answer, metadata: metadata);
  }

  Future<Message> sendMessageStream(
    String conversationId,
    String content,
    void Function(String chunk) onChunk, {
    List<String>? knowledgeBaseIds,
    String? embeddingModel,
    String? attachmentsContent,
    void Function(Message message)? onStart,
    String? systemPromptContent,
  }) async {
    final history = await _db.listMessages(conversationId);
    final locale = await _storage.getLocale();
    final config = await _storage.getRagConfig();
    final candidateLimit = _resolveCandidateLimit(config);
    final retrievalMode = config.retrievalMode;
    final queryText = _mergeQuery(content, attachmentsContent);
    final queryEmbedding = await _resolveQueryEmbedding(queryText, retrievalMode, embeddingModel);
    final disableKnowledge = knowledgeBaseIds != null && knowledgeBaseIds.isEmpty;

    final candidates = disableKnowledge
        ? <ChunkRow>[]
        : retrievalMode == 'document'
            ? <ChunkRow>[]
            : queryEmbedding != null
                ? await _db.listDocumentChunksForKnowledgeBases(
                    knowledgeBaseIds: knowledgeBaseIds,
                    limit: _resolveEmbeddingCandidateLimit(candidateLimit),
                  )
                : await _db.searchDocumentChunks(queryText, candidateLimit, knowledgeBaseIds: knowledgeBaseIds);

    final rankedChunks =
        retrievalMode == 'document' ? <RankedChunk>[] : _rankChunks(queryText, candidates, queryEmbedding);
    final filteredChunks = _applyChunkSimilarityThreshold(rankedChunks, config.retrievalSimilarityThreshold);
    final topChunks = filteredChunks.take(_contextLimit).toList();
    final evidenceItems = filteredChunks.take(_evidenceLimit).map((chunk) => chunk.evidence).toList();

    var context = '';
    var evidence = <Evidence>[];

    if (topChunks.isNotEmpty) {
      context = _buildChunkContext(topChunks, locale);
      evidence = evidenceItems;
    } else if (retrievalMode != 'chunk' && !disableKnowledge) {
      final docCandidates = await _db.searchDocuments(queryText, candidateLimit, knowledgeBaseIds: knowledgeBaseIds);
      final rankedDocs = _rankDocuments(queryText, docCandidates);
      final filteredDocs = _applyDocumentSimilarityThreshold(rankedDocs, config.retrievalSimilarityThreshold);
      final topDocs = filteredDocs.take(_contextLimit).toList();
      context = _buildContext(topDocs, locale);
      evidence = filteredDocs.take(_evidenceLimit).map((doc) => doc.evidence).toList();
    }

    final messages = _buildMessages(
      history,
      content,
      context,
      locale,
      attachmentsContent: attachmentsContent,
      systemPromptContent: systemPromptContent,
    );
    final metadata = evidence.isNotEmpty ? MessageMetadata(query: content, evidence: evidence) : null;
    final streamMessage = await _db.addMessage(conversationId, MessageRole.assistant, '');
    _activeStreamMessageIds[conversationId] = streamMessage.id;
    _activeStreamMessages[conversationId] = streamMessage;
    onStart?.call(streamMessage);
    _streamUpdates.add(
      StreamedMessageUpdate(
        conversationId: conversationId,
        messageId: streamMessage.id,
        message: streamMessage,
      ),
    );

    var fullContent = '';
    Timer? flushTimer;

    void flushUpdate() {
      final updated = Message(
        id: streamMessage.id,
        role: MessageRole.assistant,
        content: fullContent,
        createdAt: streamMessage.createdAt,
        metadata: metadata,
      );
      _activeStreamMessages[conversationId] = updated;
      _streamUpdates.add(
        StreamedMessageUpdate(
          conversationId: conversationId,
          messageId: streamMessage.id,
          message: updated,
        ),
      );
    }

    void scheduleFlush() {
      if (flushTimer != null) {
        return;
      }
      flushTimer = Timer(_streamUpdateInterval, () {
        flushTimer = null;
        flushUpdate();
      });
    }
    try {
      await _api.requestAiAnswerStream(
        AiRequestOptions(messages: messages),
        (chunk) {
          fullContent += chunk;
          _activeStreamMessages[conversationId] = Message(
            id: streamMessage.id,
            role: MessageRole.assistant,
            content: fullContent,
            createdAt: streamMessage.createdAt,
            metadata: metadata,
          );
          scheduleFlush();
          onChunk(fullContent);
        },
      );
    } catch (error) {
      flushTimer?.cancel();
      if (fullContent.isEmpty) {
        await _db.deleteMessage(streamMessage.id);
        _streamUpdates.add(
          StreamedMessageUpdate(
            conversationId: conversationId,
            messageId: streamMessage.id,
            isDeleted: true,
            isDone: true,
          ),
        );
      } else {
        flushUpdate();
        await _db.updateMessageContent(streamMessage.id, fullContent);
        _streamUpdates.add(
          StreamedMessageUpdate(
            conversationId: conversationId,
            messageId: streamMessage.id,
            message: Message(
              id: streamMessage.id,
              role: MessageRole.assistant,
              content: fullContent,
              createdAt: streamMessage.createdAt,
              metadata: metadata,
            ),
            isDone: true,
          ),
        );
      }
      _activeStreamMessageIds.remove(conversationId);
      _activeStreamMessages.remove(conversationId);
      rethrow;
    }

    flushTimer?.cancel();
    await _db.updateMessageContent(streamMessage.id, fullContent);
    await _db.updateMessageMetadata(streamMessage.id, metadata);
    final finalMessage = Message(
      id: streamMessage.id,
      role: MessageRole.assistant,
      content: fullContent,
      createdAt: streamMessage.createdAt,
      metadata: metadata,
    );
    _streamUpdates.add(
      StreamedMessageUpdate(
        conversationId: conversationId,
        messageId: streamMessage.id,
        message: finalMessage,
        isDone: true,
      ),
    );
    _activeStreamMessageIds.remove(conversationId);
    _activeStreamMessages.remove(conversationId);
    return finalMessage;
  }

  Future<Message> sendMessageStreamWithVisualization(
    String conversationId,
    String content,
    void Function(String chunk) onChunk,
    void Function(RagVisualizationStep step, RagVisualizationData data) onVisualizationUpdate, {
    List<String>? knowledgeBaseIds,
    String? embeddingModel,
    CancelToken? cancelToken,
    String? attachmentsContent,
    void Function(Message message)? onStart,
    String? systemPromptContent,
  }) async {
    final locale = await _storage.getLocale();
    final visualizationData = RagVisualizationData(
      query: content,
      candidates: [],
      selectedEvidence: [],
      context: '',
      prompt: '',
      answer: '',
      embedding: RagVisualizationEmbedding(enabled: true),
    );

    onVisualizationUpdate(RagVisualizationStep.query, visualizationData);

    final embeddingConfig = await _storage.getEmbeddingConfig();
    final overrideModel = embeddingModel?.trim();
    final resolvedEmbeddingModel = embeddingModel == null
        ? (overrideModel ?? embeddingConfig.model).trim()
        : overrideModel ?? embeddingConfig.model;
    final embeddingEnabled = embeddingModel != null
        ? embeddingModel.trim().isNotEmpty
        : embeddingConfig.url.isNotEmpty && resolvedEmbeddingModel.isNotEmpty;
    visualizationData.embedding = RagVisualizationEmbedding(
      enabled: embeddingEnabled,
      model: resolvedEmbeddingModel.isNotEmpty ? resolvedEmbeddingModel : null,
    );
    onVisualizationUpdate(RagVisualizationStep.embedding, visualizationData);

    final history = await _db.listMessages(conversationId);
    final config = await _storage.getRagConfig();
    final candidateLimit = _resolveCandidateLimit(config);
    final retrievalMode = config.retrievalMode;
    final queryText = _mergeQuery(content, attachmentsContent);
    final queryEmbedding = await _resolveQueryEmbedding(
      queryText,
      retrievalMode,
      embeddingEnabled ? embeddingModel : null,
    );
    final disableKnowledge = knowledgeBaseIds != null && knowledgeBaseIds.isEmpty;

    final candidates = disableKnowledge
        ? <ChunkRow>[]
        : retrievalMode == 'document'
            ? <ChunkRow>[]
            : queryEmbedding != null
                ? await _db.listDocumentChunksForKnowledgeBases(
                    knowledgeBaseIds: knowledgeBaseIds,
                    limit: _resolveEmbeddingCandidateLimit(candidateLimit),
                  )
                : await _db.searchDocumentChunks(queryText, candidateLimit, knowledgeBaseIds: knowledgeBaseIds);

    visualizationData.candidates = candidates.take(candidateLimit).map((candidate) {
      return RagVisualizationCandidate(
        id: candidate.id,
        documentTitle: candidate.documentTitle,
        chunkIndex: candidate.chunkIndex,
        content: candidate.content,
      );
    }).toList();
    onVisualizationUpdate(RagVisualizationStep.embedding, visualizationData);

    onVisualizationUpdate(RagVisualizationStep.retrieval, visualizationData);

    final rankedChunks =
        retrievalMode == 'document' ? <RankedChunk>[] : _rankChunks(queryText, candidates, queryEmbedding);
    final filteredChunks = _applyChunkSimilarityThreshold(rankedChunks, config.retrievalSimilarityThreshold);
    final topChunks = filteredChunks.take(_contextLimit).toList();
    final evidenceItems = filteredChunks.take(_evidenceLimit).map((chunk) => chunk.evidence).toList();

    visualizationData.candidates = filteredChunks.take(candidateLimit).map((chunk) {
      return RagVisualizationCandidate(
        id: chunk.id,
        documentTitle: chunk.documentTitle,
        chunkIndex: chunk.chunkIndex,
        content: chunk.content,
        score: chunk.score,
        similarity: chunk.evidence.similarity,
        hitRate: chunk.evidence.hitRate,
      );
    }).toList();
    visualizationData.selectedEvidence = evidenceItems;
    onVisualizationUpdate(RagVisualizationStep.retrieval, visualizationData);

    var context = '';
    var evidence = <Evidence>[];

    if (topChunks.isNotEmpty) {
      context = _buildChunkContext(topChunks, locale);
      evidence = evidenceItems;
    } else if (retrievalMode != 'chunk' && !disableKnowledge) {
      final docCandidates = await _db.searchDocuments(queryText, candidateLimit, knowledgeBaseIds: knowledgeBaseIds);
      final rankedDocs = _rankDocuments(queryText, docCandidates);
      final filteredDocs = _applyDocumentSimilarityThreshold(rankedDocs, config.retrievalSimilarityThreshold);
      final topDocs = filteredDocs.take(_contextLimit).toList();
      context = _buildContext(topDocs, locale);
      evidence = filteredDocs.take(_evidenceLimit).map((doc) => doc.evidence).toList();

      visualizationData.candidates = filteredDocs.take(candidateLimit).map((doc) {
        return RagVisualizationCandidate(
          id: doc.id,
          documentTitle: doc.title,
          content: doc.content,
          score: doc.score,
          similarity: doc.evidence.similarity,
          hitRate: doc.evidence.hitRate,
        );
      }).toList();
      visualizationData.selectedEvidence = evidence;
      onVisualizationUpdate(RagVisualizationStep.retrieval, visualizationData);
    }

    visualizationData.context = context;
    final messages = _buildMessages(
      history,
      content,
      context,
      locale,
      attachmentsContent: attachmentsContent,
      systemPromptContent: systemPromptContent,
    );
    final prompt = _buildPromptPreview(messages);
    visualizationData.prompt = prompt;
    onVisualizationUpdate(RagVisualizationStep.prompt, visualizationData);

    final metadata = evidence.isNotEmpty ? MessageMetadata(query: content, evidence: evidence) : null;

    onVisualizationUpdate(RagVisualizationStep.generating, visualizationData);

    final streamMessage = await _db.addMessage(conversationId, MessageRole.assistant, '');
    _activeStreamMessageIds[conversationId] = streamMessage.id;
    _activeStreamMessages[conversationId] = streamMessage;
    onStart?.call(streamMessage);
    _streamUpdates.add(
      StreamedMessageUpdate(
        conversationId: conversationId,
        messageId: streamMessage.id,
        message: streamMessage,
      ),
    );

    var fullContent = '';
    Timer? flushTimer;

    void flushUpdate() {
      final updated = Message(
        id: streamMessage.id,
        role: MessageRole.assistant,
        content: fullContent,
        createdAt: streamMessage.createdAt,
        metadata: metadata,
      );
      _activeStreamMessages[conversationId] = updated;
      _streamUpdates.add(
        StreamedMessageUpdate(
          conversationId: conversationId,
          messageId: streamMessage.id,
          message: updated,
        ),
      );
    }

    void scheduleFlush() {
      if (flushTimer != null) {
        return;
      }
      flushTimer = Timer(_streamUpdateInterval, () {
        flushTimer = null;
        flushUpdate();
      });
    }
    try {
      await _api.requestAiAnswerStream(
        AiRequestOptions(messages: messages),
        (chunk) {
          fullContent += chunk;
          _activeStreamMessages[conversationId] = Message(
            id: streamMessage.id,
            role: MessageRole.assistant,
            content: fullContent,
            createdAt: streamMessage.createdAt,
            metadata: metadata,
          );
          scheduleFlush();
          onChunk(fullContent);
          visualizationData.answer = fullContent;
          onVisualizationUpdate(RagVisualizationStep.generating, visualizationData);
        },
        cancelToken: cancelToken,
      );
    } catch (error) {
      flushTimer?.cancel();
      if (fullContent.isEmpty) {
        await _db.deleteMessage(streamMessage.id);
        _streamUpdates.add(
          StreamedMessageUpdate(
            conversationId: conversationId,
            messageId: streamMessage.id,
            isDeleted: true,
            isDone: true,
          ),
        );
      } else {
        flushUpdate();
        await _db.updateMessageContent(streamMessage.id, fullContent);
        _streamUpdates.add(
          StreamedMessageUpdate(
            conversationId: conversationId,
            messageId: streamMessage.id,
            message: Message(
              id: streamMessage.id,
              role: MessageRole.assistant,
              content: fullContent,
              createdAt: streamMessage.createdAt,
              metadata: metadata,
            ),
            isDone: true,
          ),
        );
      }
      _activeStreamMessageIds.remove(conversationId);
      _activeStreamMessages.remove(conversationId);
      rethrow;
    }

    flushTimer?.cancel();
    visualizationData.answer = fullContent;
    onVisualizationUpdate(RagVisualizationStep.completed, visualizationData);

    await _db.updateMessageContent(streamMessage.id, fullContent);
    await _db.updateMessageMetadata(streamMessage.id, metadata);
    final finalMessage = Message(
      id: streamMessage.id,
      role: MessageRole.assistant,
      content: fullContent,
      createdAt: streamMessage.createdAt,
      metadata: metadata,
    );
    _streamUpdates.add(
      StreamedMessageUpdate(
        conversationId: conversationId,
        messageId: streamMessage.id,
        message: finalMessage,
        isDone: true,
      ),
    );
    _activeStreamMessageIds.remove(conversationId);
    _activeStreamMessages.remove(conversationId);
    return finalMessage;
  }

  Future<_ChunkEmbeddings> _buildChunkEmbeddings({
    required String content,
    required int? chunkSizeMin,
    required int chunkSizeMax,
    required int chunkOverlap,
    void Function(EmbeddingProgress progress)? onProgress,
    String? embeddingModel,
    List<String>? chunkSeparators,
  }) async {
    onProgress?.call(EmbeddingProgress(stage: 'chunking'));
    final chunks = splitIntoChunks(
      content,
      chunkSizeMax,
      chunkOverlap,
      separators: chunkSeparators,
      chunkMinSize: chunkSizeMin,
    );
    onProgress?.call(EmbeddingProgress(stage: 'embedding', total: chunks.length, current: 0));
    final embeddings = await _embedChunks(chunks, onProgress, embeddingModel);
    if (embeddings.length != chunks.length) {
      final locale = await _storage.getLocale();
      throw StateError(translate(locale, 'error.embeddingResponseInvalid'));
    }
    return _ChunkEmbeddings(chunks: chunks, embeddings: embeddings);
  }

  Future<List<List<double>>> _embedChunks(
    List<String> chunks,
    void Function(EmbeddingProgress progress)? onProgress,
    String? embeddingModel,
  ) async {
    final embeddings = <List<double>>[];
    for (var index = 0; index < chunks.length; index += _embeddingBatchSize) {
      final batch = chunks.sublist(index, min(index + _embeddingBatchSize, chunks.length));
      final batchEmbeddings = await _api.requestEmbeddings(
        EmbeddingRequestOptions(input: batch, model: embeddingModel),
      );
      embeddings.addAll(batchEmbeddings);
      onProgress?.call(
        EmbeddingProgress(stage: 'embedding', current: embeddings.length, total: chunks.length),
      );
    }
    return embeddings;
  }

  Future<List<double>?> _resolveQueryEmbedding(
    String content,
    String retrievalMode,
    String? embeddingModel,
  ) async {
    if (retrievalMode == 'document') {
      return null;
    }
    final embeddingConfig = await _storage.getEmbeddingConfig();
    final modelOverride = embeddingModel?.trim();
    final resolvedModel = modelOverride?.isNotEmpty == true
        ? modelOverride!
        : embeddingConfig.model.trim();
    final embeddingEnabled = embeddingConfig.url.isNotEmpty && resolvedModel.isNotEmpty;
    if (!embeddingEnabled) {
      return null;
    }
    return _api.requestEmbedding(EmbeddingRequestOptions(input: content, model: resolvedModel));
  }

  List<AiMessage> _buildMessages(
    List<Message> history,
    String content,
    String context,
    String locale, {
    String? attachmentsContent,
    String? systemPromptContent,
  }) {
    final trimmedHistory = history
        .where((message) => message.role == MessageRole.user || message.role == MessageRole.assistant)
        .map((message) => AiMessage(role: message.role.name, content: message.content))
        .toList();
    if (trimmedHistory.length > 6) {
      trimmedHistory.removeRange(0, trimmedHistory.length - 6);
    }
    if (trimmedHistory.isNotEmpty && trimmedHistory.last.role == 'user' && trimmedHistory.last.content == content) {
      trimmedHistory.removeLast();
    }

    final contextLabel = translate(locale, 'prompt.contextLabel');
    final questionLabel = translate(locale, 'prompt.questionLabel');
    final attachmentLabel = translate(locale, 'prompt.attachmentLabel');
    final attachmentText = (attachmentsContent ?? '').trim();
    final questionBlock = '$questionLabel:\n$content';
    final attachmentBlock = attachmentText.isNotEmpty ? '\n\n$attachmentLabel:\n$attachmentText' : '';
    final userPrompt = context.isNotEmpty
        ? '$contextLabel:\n$context\n\n$questionBlock$attachmentBlock'
        : '$questionBlock$attachmentBlock';

    return [
      AiMessage(role: 'system', content: systemPromptContent ?? translate(locale, 'prompt.system')),
      ...trimmedHistory,
      AiMessage(role: 'user', content: userPrompt),
    ];
  }

  String _buildPromptPreview(List<AiMessage> messages) {
    return messages.map((message) => '${message.role.toUpperCase()}:\n${message.content}').join('\n\n');
  }

  String _mergeQuery(String content, String? attachmentsContent) {
    final attachmentText = attachmentsContent?.trim();
    if (attachmentText == null || attachmentText.isEmpty) {
      return content;
    }
    return '$content\n\n$attachmentText';
  }

  String _buildChunkContext(List<RankedChunk> chunks, String locale) {
    return chunks.map((chunk) {
      final trimmed = _truncate(chunk.content, 800);
      final title = chunk.documentTitle ?? translate(locale, 'context.untitled');
      final chunkLabel = translate(locale, 'context.chunkLabel', {'index': chunks.indexOf(chunk) + 1});
      return '$chunkLabel: $title #${chunk.chunkIndex}\n$trimmed';
    }).join('\n\n');
  }

  String _buildContext(List<RankedDocument> docs, String locale) {
    if (docs.isEmpty) {
      return '';
    }
    return docs.map((doc) {
      final trimmed = _truncate(doc.content, 800);
      final docLabel = translate(locale, 'context.documentLabel', {'index': docs.indexOf(doc) + 1});
      return '$docLabel: ${doc.title}\n$trimmed';
    }).join('\n\n');
  }

  int _resolveCandidateLimit(RagConfig config) {
    if (config.retrievalTopK > 0) {
      return config.retrievalTopK;
    }
    return _candidateLimit;
  }

  int _resolveEmbeddingCandidateLimit(int baseLimit) {
    return max(baseLimit * _embeddingCandidateMultiplier, baseLimit);
  }

  List<RankedChunk> _rankChunks(String query, List<ChunkRow> chunks, List<double>? queryEmbedding) {
    final terms = _extractTerms(query);
    return chunks
        .map((chunk) {
          final scored = _scoreContent(terms: terms, content: chunk.content);
          final vectorSimilarity = queryEmbedding != null ? _cosineSimilarity(queryEmbedding, _parseEmbedding(chunk.embedding)) : null;
          final similarity = vectorSimilarity ?? scored.similarity;
          final score = vectorSimilarity ?? scored.finalScore;
          return RankedChunk(
            id: chunk.id,
            documentId: chunk.documentId,
            chunkIndex: chunk.chunkIndex,
            content: chunk.content,
            documentTitle: chunk.documentTitle,
            embedding: chunk.embedding,
            score: score,
            evidence: Evidence(
              id: chunk.id,
              documentId: chunk.documentId,
              documentTitle: chunk.documentTitle,
              chunkIndex: chunk.chunkIndex,
              snippet: scored.snippet,
              similarity: similarity,
              hitRate: scored.hitRate,
              updatedAt: chunk.documentUpdatedAt,
            ),
          );
        })
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
  }

  List<RankedChunk> _applyChunkSimilarityThreshold(List<RankedChunk> chunks, double threshold) {
    if (threshold <= 0) {
      return chunks;
    }
    return chunks.where((chunk) => (chunk.evidence.similarity) >= threshold).toList();
  }

  List<RankedDocument> _rankDocuments(String query, List<DocumentRow> docs) {
    final terms = _extractTerms(query);
    return docs
        .map((doc) {
          final scored = _scoreContent(terms: terms, content: doc.content);
          return RankedDocument(
            id: doc.id,
            title: doc.title,
            content: doc.content,
            updatedAt: doc.updatedAt,
            score: scored.finalScore,
            evidence: Evidence(
              id: doc.id,
              documentId: doc.id,
              documentTitle: doc.title,
              snippet: scored.snippet,
              similarity: scored.similarity,
              hitRate: scored.hitRate,
              updatedAt: doc.updatedAt,
            ),
          );
        })
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
  }

  List<RankedDocument> _applyDocumentSimilarityThreshold(List<RankedDocument> docs, double threshold) {
    if (threshold <= 0) {
      return docs;
    }
    return docs.where((doc) => (doc.evidence.similarity) >= threshold).toList();
  }

  _ScoreResult _scoreContent({required List<String> terms, required String content}) {
    final normalizedContent = content.toLowerCase();
    final hitRate = _calculateHitRate(terms, normalizedContent);
    final similarity = _calculateSimilarity(terms, normalizedContent);
    return _ScoreResult(
      hitRate: hitRate,
      similarity: similarity,
      finalScore: similarity,
      snippet: _buildSnippet(content, terms),
    );
  }

  List<String> _extractTerms(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return [];
    }
    final matches = RegExp(r'[a-z0-9]+|[\u4e00-\u9fff]+').allMatches(normalized);
    if (matches.isEmpty) {
      return [normalized];
    }
    return matches.map((match) => match.group(0) ?? '').where((item) => item.isNotEmpty).toList();
  }

  double _calculateHitRate(List<String> terms, String content) {
    if (terms.isEmpty) {
      return 0;
    }
    final matched = terms.where((term) => term.isNotEmpty && content.contains(term)).length;
    return matched / terms.length;
  }

  double _calculateSimilarity(List<String> terms, String content) {
    if (terms.isEmpty) {
      return 0;
    }
    final tokens = _extractTerms(content.substring(0, min(2000, content.length)));
    final tokenSet = tokens.toSet();
    final matched = terms.where((term) => term.isNotEmpty && content.contains(term)).length;
    final density = tokenSet.isNotEmpty ? matched / tokenSet.length : 0;
    final score = (matched / terms.length) * 0.7 + density * 0.3;
    return score.clamp(0, 1);
  }

  List<double>? _parseEmbedding(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) {
        return null;
      }
      final list = decoded.map((item) => item is num ? item.toDouble() : null).whereType<double>().toList();
      return list.isEmpty ? null : list;
    } catch (_) {
      return null;
    }
  }

  double? _cosineSimilarity(List<double> a, List<double>? b) {
    if (b == null || a.isEmpty || b.isEmpty || a.length != b.length) {
      return null;
    }
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var index = 0; index < a.length; index += 1) {
      final x = a[index];
      final y = b[index];
      dot += x * y;
      normA += x * x;
      normB += y * y;
    }
    if (normA == 0 || normB == 0) {
      return null;
    }
    final similarity = dot / (sqrt(normA) * sqrt(normB));
    return similarity.clamp(0, 1);
  }

  String _buildSnippet(String content, List<String> terms) {
    if (content.isEmpty) {
      return '';
    }
    if (terms.isEmpty) {
      return _truncate(content, 160);
    }
    final normalized = content.toLowerCase();
    var matchIndex = -1;
    var matchLength = 0;
    for (final term in terms) {
      if (term.isEmpty) {
        continue;
      }
      final index = normalized.indexOf(term);
      if (index != -1 && (matchIndex == -1 || index < matchIndex)) {
        matchIndex = index;
        matchLength = term.length;
      }
    }
    if (matchIndex == -1) {
      return _truncate(content, 160);
    }
    final start = max(0, matchIndex - 40);
    final end = min(content.length, matchIndex + matchLength + 80);
    var snippet = content.substring(start, end).trim();
    if (start > 0) {
      snippet = '...$snippet';
    }
    if (end < content.length) {
      snippet = '$snippet...';
    }
    return snippet;
  }

  String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength)}...';
  }
}

class _ChunkEmbeddings {
  _ChunkEmbeddings({required this.chunks, required this.embeddings});

  final List<String> chunks;
  final List<List<double>> embeddings;
}

class RankedChunk {
  RankedChunk({
    required this.id,
    required this.documentId,
    required this.chunkIndex,
    required this.content,
    required this.documentTitle,
    required this.embedding,
    required this.score,
    required this.evidence,
  });

  final String id;
  final String documentId;
  final int chunkIndex;
  final String content;
  final String? documentTitle;
  final String? embedding;
  final double score;
  final Evidence evidence;
}

class RankedDocument {
  RankedDocument({
    required this.id,
    required this.title,
    required this.content,
    required this.updatedAt,
    required this.score,
    required this.evidence,
  });

  final String id;
  final String title;
  final String content;
  final String updatedAt;
  final double score;
  final Evidence evidence;
}

class _ScoreResult {
  _ScoreResult({
    required this.hitRate,
    required this.similarity,
    required this.finalScore,
    required this.snippet,
  });

  final double hitRate;
  final double similarity;
  final double finalScore;
  final String snippet;
}
