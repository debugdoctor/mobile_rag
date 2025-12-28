import 'dart:convert';

enum MessageRole { user, assistant, system }

class KnowledgeBase {
  KnowledgeBase({
    required this.id,
    required this.name,
    this.description,
    this.documentCount,
    this.updatedAt,
    this.embeddingModel,
    this.chunkSeparators,
    this.chunkSizeMin,
    this.chunkSizeMax,
    this.chunkOverlap,
    this.maxFileSizeMb,
    this.status,
  });

  final String id;
  final String name;
  final String? description;
  final int? documentCount;
  final String? updatedAt;
  final String? embeddingModel;
  final String? chunkSeparators;
  final int? chunkSizeMin;
  final int? chunkSizeMax;
  final int? chunkOverlap;
  final int? maxFileSizeMb;
  final String? status;
}

class Document {
  Document({
    required this.id,
    required this.knowledgeBaseId,
    required this.title,
    this.content,
    this.updatedAt,
  });

  final String id;
  final String knowledgeBaseId;
  final String title;
  final String? content;
  final String? updatedAt;
}

class DocumentChunk {
  DocumentChunk({
    required this.id,
    required this.documentId,
    required this.chunkIndex,
    required this.content,
    this.createdAt,
    this.documentTitle,
  });

  final String id;
  final String documentId;
  final int chunkIndex;
  final String content;
  final String? createdAt;
  final String? documentTitle;
}

class Conversation {
  Conversation({
    required this.id,
    this.title,
    this.summary,
    this.updatedAt,
  });

  final String id;
  final String? title;
  final String? summary;
  final String? updatedAt;
}

class Evidence {
  Evidence({
    required this.id,
    this.documentId,
    this.documentTitle,
    this.chunkIndex,
    required this.snippet,
    required this.similarity,
    required this.hitRate,
    this.updatedAt,
  });

  final String id;
  final String? documentId;
  final String? documentTitle;
  final int? chunkIndex;
  final String snippet;
  final double similarity;
  final double hitRate;
  final String? updatedAt;

  factory Evidence.fromJson(Map<String, dynamic> json) {
    return Evidence(
      id: json['id'] as String,
      documentId: json['documentId'] as String?,
      documentTitle: json['documentTitle'] as String?,
      chunkIndex: json['chunkIndex'] as int?,
      snippet: json['snippet'] as String? ?? '',
      similarity: (json['similarity'] as num?)?.toDouble() ?? 0,
      hitRate: (json['hitRate'] as num?)?.toDouble() ?? 0,
      updatedAt: json['updatedAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'documentId': documentId,
        'documentTitle': documentTitle,
        'chunkIndex': chunkIndex,
        'snippet': snippet,
        'similarity': similarity,
        'hitRate': hitRate,
        'updatedAt': updatedAt,
      };
}

class MessageMetadata {
  MessageMetadata({
    this.query,
    this.evidence,
  });

  final String? query;
  final List<Evidence>? evidence;

  factory MessageMetadata.fromJson(Map<String, dynamic> json) {
    final evidenceJson = json['evidence'];
    return MessageMetadata(
      query: json['query'] as String?,
      evidence: evidenceJson is List
          ? evidenceJson
              .whereType<Map<String, dynamic>>()
              .map(Evidence.fromJson)
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'query': query,
        'evidence': evidence?.map((item) => item.toJson()).toList(),
      };

  static MessageMetadata? parse(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return MessageMetadata.fromJson(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static String? serialize(MessageMetadata? metadata) {
    if (metadata == null) {
      return null;
    }
    try {
      return jsonEncode(metadata.toJson());
    } catch (_) {
      return null;
    }
  }
}

class Message {
  Message({
    required this.id,
    required this.role,
    required this.content,
    this.createdAt,
    this.metadata,
  });

  final String id;
  final MessageRole role;
  final String content;
  final String? createdAt;
  final MessageMetadata? metadata;
}
