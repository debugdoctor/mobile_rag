import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

import '../data/database/app_database.dart' as db;
import '../domain/models.dart';
import '../utils/chunking.dart';
import '../utils/ids.dart';

class DbService {
  DbService(this._db);

  final db.AppDatabase _db;

  Future<List<KnowledgeBase>> listKnowledgeBases() async {
    final rows = await _db.customSelect(
      '''
      SELECT kb.id,
             kb.name,
             kb.description,
             kb.updated_at,
             kb.embedding_model,
             kb.chunk_separators,
             kb.chunk_size_min,
             kb.chunk_size_max,
             kb.chunk_overlap,
             kb.max_file_size_mb,
             COUNT(doc.id) AS document_count
        FROM knowledge_bases kb
        LEFT JOIN documents doc ON doc.knowledge_base_id = kb.id
    GROUP BY kb.id
    ORDER BY kb.updated_at DESC
      ''',
      readsFrom: {_db.knowledgeBases, _db.documents},
    ).get();

    return rows.map((row) {
      final data = row.data;
      return KnowledgeBase(
        id: data['id'] as String,
        name: data['name'] as String,
        description: data['description'] as String?,
        updatedAt: data['updated_at'] as String,
        embeddingModel: data['embedding_model'] as String?,
        chunkSeparators: data['chunk_separators'] as String?,
        chunkSizeMin: data['chunk_size_min'] as int?,
        chunkSizeMax: data['chunk_size_max'] as int?,
        chunkOverlap: data['chunk_overlap'] as int?,
        maxFileSizeMb: data['max_file_size_mb'] as int?,
        documentCount: (data['document_count'] as int?) ?? 0,
        status: 'ready',
      );
    }).toList();
  }

  Future<KnowledgeBase?> getKnowledgeBase(String id) async {
    final rows = await _db.customSelect(
      '''
      SELECT kb.id,
             kb.name,
             kb.description,
             kb.updated_at,
             kb.embedding_model,
             kb.chunk_separators,
             kb.chunk_size_min,
             kb.chunk_size_max,
             kb.chunk_overlap,
             kb.max_file_size_mb,
             COUNT(doc.id) AS document_count
        FROM knowledge_bases kb
        LEFT JOIN documents doc ON doc.knowledge_base_id = kb.id
       WHERE kb.id = ?
    GROUP BY kb.id
      ''',
      readsFrom: {_db.knowledgeBases, _db.documents},
      variables: [Variable<String>(id)],
    ).get();

    if (rows.isEmpty) {
      return null;
    }
    final data = rows.first.data;
    return KnowledgeBase(
      id: data['id'] as String,
      name: data['name'] as String,
      description: data['description'] as String?,
      updatedAt: data['updated_at'] as String,
      embeddingModel: data['embedding_model'] as String?,
      chunkSeparators: data['chunk_separators'] as String?,
      chunkSizeMin: data['chunk_size_min'] as int?,
      chunkSizeMax: data['chunk_size_max'] as int?,
      chunkOverlap: data['chunk_overlap'] as int?,
      maxFileSizeMb: data['max_file_size_mb'] as int?,
      documentCount: (data['document_count'] as int?) ?? 0,
      status: 'ready',
    );
  }

  Future<KnowledgeBase> createKnowledgeBase({
    required String name,
    String? description,
    String? embeddingModel,
    String? chunkSeparators,
    int? chunkSizeMin,
    int? chunkSizeMax,
    int? chunkOverlap,
    int? maxFileSizeMb,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw StateError('Knowledge base name is required.');
    }
    final now = DateTime.now().toIso8601String();
    final id = createId('kb');
    await _db.into(_db.knowledgeBases).insert(
          db.KnowledgeBasesCompanion.insert(
            id: id,
            name: trimmedName,
            description: Value(_normalizeNullableText(description)),
            embeddingModel: Value(_normalizeNullableText(embeddingModel)),
            chunkSeparators: Value(_normalizeSeparatorText(chunkSeparators)),
            chunkSizeMin: Value(_normalizePositiveInt(chunkSizeMin)),
            chunkSizeMax: Value(_normalizePositiveInt(chunkSizeMax)),
            chunkOverlap: Value(_normalizePositiveInt(chunkOverlap)),
            maxFileSizeMb: Value(_normalizePositiveInt(maxFileSizeMb)),
            updatedAt: now,
          ),
        );

    return KnowledgeBase(
      id: id,
      name: trimmedName,
      description: description?.trim().isEmpty == true ? null : description?.trim(),
      updatedAt: now,
      embeddingModel: embeddingModel?.trim().isEmpty == true ? null : embeddingModel?.trim(),
      chunkSeparators: chunkSeparators?.trim().isEmpty == true ? null : chunkSeparators?.trim(),
      chunkSizeMin: _normalizePositiveInt(chunkSizeMin),
      chunkSizeMax: _normalizePositiveInt(chunkSizeMax),
      chunkOverlap: _normalizePositiveInt(chunkOverlap),
      maxFileSizeMb: _normalizePositiveInt(maxFileSizeMb),
      documentCount: 0,
      status: 'ready',
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
    final existing = await getKnowledgeBase(id);
    if (existing == null) {
      return null;
    }
    final now = DateTime.now().toIso8601String();
    final nextName = name != null && name.trim().isNotEmpty ? name.trim() : existing.name;
    final nextDescription = description != null ? _normalizeNullableText(description) : existing.description;
    final nextEmbeddingModel = embeddingModel != null ? _normalizeNullableText(embeddingModel) : existing.embeddingModel;
    final nextChunkSeparators = chunkSeparators != null
        ? _normalizeSeparatorText(chunkSeparators)
        : existing.chunkSeparators;
    final nextChunkSizeMin = chunkSizeMin != null
        ? _normalizePositiveInt(chunkSizeMin)
        : existing.chunkSizeMin;
    final nextChunkSizeMax = chunkSizeMax != null
        ? _normalizePositiveInt(chunkSizeMax)
        : existing.chunkSizeMax;
    final nextChunkOverlap = chunkOverlap != null
        ? _normalizePositiveInt(chunkOverlap)
        : existing.chunkOverlap;
    final nextMaxFileSize = maxFileSizeMb != null
        ? _normalizePositiveInt(maxFileSizeMb)
        : existing.maxFileSizeMb;

    await (_db.update(_db.knowledgeBases)..where((tbl) => tbl.id.equals(id))).write(
      db.KnowledgeBasesCompanion(
        name: Value(nextName),
        description: Value(nextDescription),
        embeddingModel: Value(nextEmbeddingModel),
        chunkSeparators: Value(nextChunkSeparators),
        chunkSizeMin: Value(nextChunkSizeMin),
        chunkSizeMax: Value(nextChunkSizeMax),
        chunkOverlap: Value(nextChunkOverlap),
        maxFileSizeMb: Value(nextMaxFileSize),
        updatedAt: Value(now),
      ),
    );

    return KnowledgeBase(
      id: existing.id,
      name: nextName,
      description: nextDescription,
      updatedAt: now,
      embeddingModel: nextEmbeddingModel,
      chunkSeparators: nextChunkSeparators,
      chunkSizeMin: nextChunkSizeMin,
      chunkSizeMax: nextChunkSizeMax,
      chunkOverlap: nextChunkOverlap,
      maxFileSizeMb: nextMaxFileSize,
      documentCount: existing.documentCount,
      status: existing.status,
    );
  }

  Future<void> deleteKnowledgeBase(String id) async {
    await _db.customStatement(
      'DELETE FROM document_chunks WHERE document_id IN (SELECT id FROM documents WHERE knowledge_base_id = ?)',
      [id],
    );
    await (_db.delete(_db.documents)..where((tbl) => tbl.knowledgeBaseId.equals(id))).go();
    await (_db.delete(_db.knowledgeBases)..where((tbl) => tbl.id.equals(id))).go();
  }

  Future<void> clearKnowledgeBaseDocuments(String knowledgeBaseId) async {
    await _db.customStatement(
      'DELETE FROM document_chunks WHERE document_id IN (SELECT id FROM documents WHERE knowledge_base_id = ?)',
      [knowledgeBaseId],
    );
    await (_db.delete(_db.documents)..where((tbl) => tbl.knowledgeBaseId.equals(knowledgeBaseId))).go();
    await (_db.update(_db.knowledgeBases)..where((tbl) => tbl.id.equals(knowledgeBaseId))).write(
      db.KnowledgeBasesCompanion(updatedAt: Value(DateTime.now().toIso8601String())),
    );
  }

  Future<void> clearAllDocuments() async {
    await _db.delete(_db.documentChunks).go();
    await _db.delete(_db.documents).go();
    await _db.update(_db.knowledgeBases).write(
      db.KnowledgeBasesCompanion(updatedAt: Value(DateTime.now().toIso8601String())),
    );
  }

  Future<List<Document>> listDocuments(String knowledgeBaseId) async {
    final rows = await (_db.select(_db.documents)
          ..where((tbl) => tbl.knowledgeBaseId.equals(knowledgeBaseId))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)]))
        .get();

    return rows
        .map((row) => Document(
              id: row.id,
              knowledgeBaseId: row.knowledgeBaseId,
              title: row.title,
              updatedAt: row.updatedAt,
            ))
        .toList();
  }

  Future<Document?> getDocument(String documentId) async {
    final row = await (_db.select(_db.documents)..where((tbl) => tbl.id.equals(documentId))).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return Document(
      id: row.id,
      knowledgeBaseId: row.knowledgeBaseId,
      title: row.title,
      content: row.content,
      updatedAt: row.updatedAt,
    );
  }

  Future<Document> createDocument({
    required String knowledgeBaseId,
    required String title,
    required String content,
    int? chunkSizeMin,
    required int chunkSizeMax,
    required int chunkOverlap,
    List<String>? chunks,
    List<List<double>>? embeddings,
  }) async {
    final id = createId('doc');
    final now = DateTime.now().toIso8601String();
    final trimmedTitle = title.trim().isEmpty ? 'Untitled' : title.trim();

    await _db.into(_db.documents).insert(
          db.DocumentsCompanion.insert(
            id: id,
            knowledgeBaseId: knowledgeBaseId,
            title: trimmedTitle,
            content: content,
            updatedAt: now,
          ),
        );

    await _replaceDocumentChunks(
      id,
      content,
      chunkSizeMax,
      chunkOverlap,
      minChunkSize: chunkSizeMin,
      chunks: chunks,
      embeddings: embeddings,
    );

    await (_db.update(_db.knowledgeBases)..where((tbl) => tbl.id.equals(knowledgeBaseId))).write(
      db.KnowledgeBasesCompanion(updatedAt: Value(now)),
    );

    return Document(
      id: id,
      knowledgeBaseId: knowledgeBaseId,
      title: trimmedTitle,
      content: content,
      updatedAt: now,
    );
  }

  Future<Document?> updateDocument({
    required String documentId,
    String? title,
    String? content,
    int? chunkSizeMin,
    int? chunkSizeMax,
    int? chunkOverlap,
    List<String>? chunks,
    List<List<double>>? embeddings,
  }) async {
    final existing = await getDocument(documentId);
    if (existing == null) {
      return null;
    }
    final nextTitle = title != null && title.trim().isNotEmpty ? title.trim() : existing.title;
    final nextContent = content ?? existing.content ?? '';
    final now = DateTime.now().toIso8601String();

    await (_db.update(_db.documents)..where((tbl) => tbl.id.equals(documentId))).write(
      db.DocumentsCompanion(
        title: Value(nextTitle),
        content: Value(nextContent),
        updatedAt: Value(now),
      ),
    );

    if (content != null) {
      await _replaceDocumentChunks(
        documentId,
        nextContent,
        chunkSizeMax ?? 800,
        chunkOverlap ?? 120,
        minChunkSize: chunkSizeMin,
        chunks: chunks,
        embeddings: embeddings,
      );
    }

    await (_db.update(_db.knowledgeBases)
          ..where((tbl) => tbl.id.equals(existing.knowledgeBaseId)))
        .write(db.KnowledgeBasesCompanion(updatedAt: Value(now)));

    return Document(
      id: existing.id,
      knowledgeBaseId: existing.knowledgeBaseId,
      title: nextTitle,
      content: content != null ? nextContent : null,
      updatedAt: now,
    );
  }

  Future<void> deleteDocument(String documentId) async {
    final existing = await getDocument(documentId);
    if (existing == null) {
      return;
    }
    await (_db.delete(_db.documentChunks)..where((tbl) => tbl.documentId.equals(documentId))).go();
    await (_db.delete(_db.documents)..where((tbl) => tbl.id.equals(documentId))).go();
    await (_db.update(_db.knowledgeBases)
          ..where((tbl) => tbl.id.equals(existing.knowledgeBaseId)))
        .write(db.KnowledgeBasesCompanion(updatedAt: Value(DateTime.now().toIso8601String())));
  }

  Future<List<DocumentChunk>> listDocumentChunks(String documentId) async {
    final rows = await (_db.select(_db.documentChunks)
          ..where((tbl) => tbl.documentId.equals(documentId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.chunkIndex)]))
        .get();

    return rows
        .map((row) => DocumentChunk(
              id: row.id,
              documentId: row.documentId,
              chunkIndex: row.chunkIndex,
              content: row.content,
              createdAt: row.createdAt,
            ))
        .toList();
  }

  Future<void> rebuildDocumentChunks({
    required String documentId,
    required String content,
    int? chunkSizeMin,
    required int chunkSizeMax,
    required int chunkOverlap,
    List<String>? chunks,
    List<List<double>>? embeddings,
    List<String>? separators,
  }) async {
    await _replaceDocumentChunks(
      documentId,
      content,
      chunkSizeMax,
      chunkOverlap,
      minChunkSize: chunkSizeMin,
      chunks: chunks,
      embeddings: embeddings,
      separators: separators,
    );
  }

  Future<List<ChunkRow>> listDocumentChunksForKnowledgeBases({
    List<String>? knowledgeBaseIds,
  }) async {
    final params = <Variable<Object>>[];
    final conditions = <String>[];
    if (knowledgeBaseIds != null && knowledgeBaseIds.isNotEmpty) {
      final placeholders = List.filled(knowledgeBaseIds.length, '?').join(', ');
      conditions.add('doc.knowledge_base_id IN ($placeholders)');
      params.addAll(knowledgeBaseIds.map((id) => Variable<String>(id)));
    }
    final whereClause = conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

    final rows = await _db.customSelect(
      '''
      SELECT chunk.id,
             chunk.document_id,
             chunk.chunk_index,
             chunk.content,
             chunk.created_at,
             chunk.embedding,
             doc.title AS document_title,
             doc.updated_at AS document_updated_at
        FROM document_chunks chunk
        JOIN documents doc ON doc.id = chunk.document_id
        $whereClause
    ORDER BY doc.updated_at DESC, chunk.chunk_index ASC
      ''',
      readsFrom: {_db.documentChunks, _db.documents},
      variables: params,
    ).get();

    return rows.map((row) => ChunkRow.fromData(row.data)).toList();
  }

  Future<List<ChunkRow>> searchDocumentChunks(
    String query,
    int limit, {
    List<String>? knowledgeBaseIds,
  }) async {
    final pattern = '%$query%';
    final conditions = <String>['chunk.content LIKE ?'];
    final params = <Variable<Object>>[Variable<String>(pattern)];
    if (knowledgeBaseIds != null && knowledgeBaseIds.isNotEmpty) {
      final placeholders = List.filled(knowledgeBaseIds.length, '?').join(', ');
      conditions.add('doc.knowledge_base_id IN ($placeholders)');
      params.addAll(knowledgeBaseIds.map((id) => Variable<String>(id)));
    }
    final whereClause = 'WHERE ${conditions.join(' AND ')}';

    final rows = await _db.customSelect(
      '''
      SELECT chunk.id,
             chunk.document_id,
             chunk.chunk_index,
             chunk.content,
             chunk.created_at,
             chunk.embedding,
             doc.title AS document_title,
             doc.updated_at AS document_updated_at
        FROM document_chunks chunk
        JOIN documents doc ON doc.id = chunk.document_id
        $whereClause
    ORDER BY doc.updated_at DESC
       LIMIT ?
      ''',
      readsFrom: {_db.documentChunks, _db.documents},
      variables: [...params, Variable<int>(limit)],
    ).get();

    return rows.map((row) => ChunkRow.fromData(row.data)).toList();
  }

  Future<List<DocumentRow>> searchDocuments(
    String query,
    int limit, {
    List<String>? knowledgeBaseIds,
  }) async {
    final pattern = '%$query%';
    final conditions = <String>['(title LIKE ? OR content LIKE ?)'];
    final params = <Variable<Object>>[Variable<String>(pattern), Variable<String>(pattern)];
    if (knowledgeBaseIds != null && knowledgeBaseIds.isNotEmpty) {
      final placeholders = List.filled(knowledgeBaseIds.length, '?').join(', ');
      conditions.add('knowledge_base_id IN ($placeholders)');
      params.addAll(knowledgeBaseIds.map((id) => Variable<String>(id)));
    }
    final whereClause = conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

    final rows = await _db.customSelect(
      '''
      SELECT id, knowledge_base_id, title, content, updated_at
        FROM documents
        $whereClause
    ORDER BY updated_at DESC
       LIMIT ?
      ''',
      readsFrom: {_db.documents},
      variables: [...params, Variable<int>(limit)],
    ).get();

    return rows.map((row) => DocumentRow.fromData(row.data)).toList();
  }

  Future<List<Conversation>> listConversations() async {
    final rows = await (_db.select(_db.conversations)
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)]))
        .get();
    return rows
        .map((row) => Conversation(
              id: row.id,
              title: row.title,
              summary: row.summary,
              updatedAt: row.updatedAt,
            ))
        .toList();
  }

  Future<Conversation?> getLatestConversation() async {
    final row = await (_db.select(_db.conversations)
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)])
          ..limit(1))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return Conversation(
      id: row.id,
      title: row.title,
      summary: row.summary,
      updatedAt: row.updatedAt,
    );
  }

  Future<Conversation> createConversation([String? title]) async {
    final id = createId('conv');
    final now = DateTime.now().toIso8601String();
    await _db.into(_db.conversations).insert(
          db.ConversationsCompanion.insert(
            id: id,
            title: Value(_normalizeNullableText(title)),
            summary: const Value(null),
            updatedAt: now,
          ),
        );
    return Conversation(id: id, title: title?.trim().isEmpty == true ? null : title?.trim(), updatedAt: now);
  }

  Future<Conversation?> updateConversation(
    String id, {
    String? title,
    String? summary,
    bool touch = true,
  }) async {
    final existing = await (_db.select(_db.conversations)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
    if (existing == null) {
      return null;
    }
    final nextTitle = title != null ? _normalizeNullableText(title) : existing.title;
    final nextSummary = summary != null ? _normalizeNullableText(summary) : existing.summary;
    final updatedAt = touch ? DateTime.now().toIso8601String() : existing.updatedAt;

    await (_db.update(_db.conversations)..where((tbl) => tbl.id.equals(id))).write(
      db.ConversationsCompanion(
        title: Value(nextTitle),
        summary: Value(nextSummary),
        updatedAt: Value(updatedAt),
      ),
    );

    return Conversation(id: id, title: nextTitle, summary: nextSummary, updatedAt: updatedAt);
  }

  Future<void> deleteConversation(String conversationId) async {
    await (_db.delete(_db.messages)..where((tbl) => tbl.conversationId.equals(conversationId))).go();
    await (_db.delete(_db.conversations)..where((tbl) => tbl.id.equals(conversationId))).go();
  }

  Future<List<Message>> listMessages(String conversationId) async {
    final rows = await (_db.select(_db.messages)
          ..where((tbl) => tbl.conversationId.equals(conversationId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
        .get();

    return rows
        .map((row) => Message(
              id: row.id,
              role: _parseRole(row.role),
              content: row.content,
              createdAt: row.createdAt,
              metadata: MessageMetadata.parse(row.metadata),
            ))
        .toList();
  }

  Future<Message> addMessage(
    String conversationId,
    MessageRole role,
    String content, {
    MessageMetadata? metadata,
  }) async {
    final id = createId(role.name);
    final now = DateTime.now().toIso8601String();
    final serialized = MessageMetadata.serialize(metadata);

    await _db.into(_db.messages).insert(
          db.MessagesCompanion.insert(
            id: id,
            conversationId: conversationId,
            role: role.name,
            content: content,
            createdAt: now,
            metadata: Value(serialized),
          ),
        );

    await (_db.update(_db.conversations)..where((tbl) => tbl.id.equals(conversationId))).write(
      db.ConversationsCompanion(updatedAt: Value(now)),
    );

    return Message(id: id, role: role, content: content, createdAt: now, metadata: metadata);
  }

  Future<Map<String, String?>> getSettings(List<String> keys) async {
    if (keys.isEmpty) {
      return {};
    }
    final rows = await (_db.select(_db.settings)..where((tbl) => tbl.key.isIn(keys))).get();
    final Map<String, String?> result = {for (final key in keys) key: null};
    for (final row in rows) {
      result[row.key] = row.value;
    }
    return result;
  }

  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      await (_db.delete(_db.settings)..where((tbl) => tbl.key.equals(key))).go();
      return;
    }
    await _db.into(_db.settings).insertOnConflictUpdate(
          db.SettingsCompanion.insert(key: key, value: Value(value)),
        );
  }

  Future<void> close() => _db.close();

  Future<void> _replaceDocumentChunks(
    String documentId,
    String content,
    int chunkSizeMax,
    int chunkOverlap, {
    int? minChunkSize,
    List<String>? chunks,
    List<List<double>>? embeddings,
    List<String>? separators,
  }) async {
    await (_db.delete(_db.documentChunks)..where((tbl) => tbl.documentId.equals(documentId))).go();

    final resolvedChunks = chunks ?? splitIntoChunks(
      content,
      chunkSizeMax,
      chunkOverlap,
      separators: separators,
      chunkMinSize: minChunkSize,
    );
    if (resolvedChunks.isEmpty) {
      return;
    }
    if (embeddings != null && embeddings.length != resolvedChunks.length) {
      throw StateError('Embedding count does not match chunk count.');
    }
    final now = DateTime.now().toIso8601String();
    for (var index = 0; index < resolvedChunks.length; index += 1) {
      final embedding = embeddings != null ? jsonEncode(embeddings[index]) : null;
      await _db.into(_db.documentChunks).insert(
            db.DocumentChunksCompanion.insert(
              id: createId('chunk'),
              documentId: documentId,
              chunkIndex: index + 1,
              content: resolvedChunks[index],
              createdAt: now,
              embedding: Value(embedding),
            ),
          );
    }
  }

  MessageRole _parseRole(String value) {
    return MessageRole.values.firstWhereOrNull((role) => role.name == value) ?? MessageRole.system;
  }

  String? _normalizeNullableText(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _normalizeSeparatorText(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int? _normalizePositiveInt(int? value) {
    if (value == null) {
      return null;
    }
    final parsed = value.round();
    if (parsed <= 0) {
      return null;
    }
    return parsed;
  }
}

class ChunkRow {
  ChunkRow({
    required this.id,
    required this.documentId,
    required this.chunkIndex,
    required this.content,
    required this.createdAt,
    required this.embedding,
    required this.documentTitle,
    required this.documentUpdatedAt,
  });

  final String id;
  final String documentId;
  final int chunkIndex;
  final String content;
  final String createdAt;
  final String? embedding;
  final String? documentTitle;
  final String? documentUpdatedAt;

  factory ChunkRow.fromData(Map<String, dynamic> data) {
    return ChunkRow(
      id: data['id'] as String,
      documentId: data['document_id'] as String,
      chunkIndex: data['chunk_index'] as int,
      content: data['content'] as String,
      createdAt: data['created_at'] as String,
      embedding: data['embedding'] as String?,
      documentTitle: data['document_title'] as String?,
      documentUpdatedAt: data['document_updated_at'] as String?,
    );
  }
}

class DocumentRow {
  DocumentRow({
    required this.id,
    required this.knowledgeBaseId,
    required this.title,
    required this.content,
    required this.updatedAt,
  });

  final String id;
  final String knowledgeBaseId;
  final String title;
  final String content;
  final String updatedAt;

  factory DocumentRow.fromData(Map<String, dynamic> data) {
    return DocumentRow(
      id: data['id'] as String,
      knowledgeBaseId: data['knowledge_base_id'] as String,
      title: data['title'] as String,
      content: data['content'] as String,
      updatedAt: data['updated_at'] as String,
    );
  }
}
