import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:path_provider/path_provider.dart';

import '../core/i18n.dart';
import '../domain/models.dart';
import '../services/db_service.dart';

const _storageKeys = {
  'locale': 'app.locale',
  'aiUrl': 'rag.config.aiUrl',
  'aiKey': 'rag.config.aiKey',
  'aiModel': 'rag.config.aiModel',
  'aiModels': 'rag.config.aiModels',
  'aiTemperature': 'rag.config.aiTemperature',
  'aiTopP': 'rag.config.aiTopP',
  'aiMaxTokens': 'rag.config.aiMaxTokens',
  'aiPresencePenalty': 'rag.config.aiPresencePenalty',
  'aiFrequencyPenalty': 'rag.config.aiFrequencyPenalty',
  'embeddingUrl': 'rag.config.embeddingUrl',
  'embeddingKey': 'rag.config.embeddingKey',
  'embeddingModel': 'rag.config.embeddingModel',
  'embeddingModels': 'rag.config.embeddingModels',
  'encryptionKeyId': 'rag.config.encryptionKeyId',
  'encryptionKeyLost': 'rag.config.encryptionKeyLost',
  'chunkSize': 'rag.config.chunkSize',
  'chunkOverlap': 'rag.config.chunkOverlap',
  'maxFileSizeMb': 'rag.config.maxFileSizeMb',
  'retrievalTopK': 'rag.config.retrievalTopK',
  'retrievalMode': 'rag.config.retrievalMode',
  'retrievalSimilarityThreshold': 'rag.config.retrievalSimilarityThreshold',
  'promptTemplates': 'rag.config.promptTemplates',
  'promptSelections': 'rag.config.promptSelections',
};

const defaultRagConfig = RagConfig(
  chunkSize: 800,
  chunkOverlap: 120,
  maxFileSizeMb: 5,
  retrievalTopK: 12,
  retrievalMode: 'hybrid',
  retrievalSimilarityThreshold: 0,
);

const _defaultPromptTemplate = PromptTemplate(
  id: defaultPromptTemplateId,
  title: 'Default prompt',
  content: '',
);

class AiConfig {
  const AiConfig({
    required this.url,
    required this.apiKey,
    required this.model,
    required this.models,
    this.temperature,
    this.topP,
    this.maxTokens,
    this.presencePenalty,
    this.frequencyPenalty,
  });

  final String url;
  final String apiKey;
  final String model;
  final List<String> models;
  final double? temperature;
  final double? topP;
  final int? maxTokens;
  final double? presencePenalty;
  final double? frequencyPenalty;
}

class EmbeddingConfig {
  const EmbeddingConfig({
    required this.url,
    required this.apiKey,
    required this.model,
    required this.models,
  });

  final String url;
  final String apiKey;
  final String model;
  final List<String> models;
}

class RagConfig {
  const RagConfig({
    required this.chunkSize,
    required this.chunkOverlap,
    required this.maxFileSizeMb,
    required this.retrievalTopK,
    required this.retrievalMode,
    required this.retrievalSimilarityThreshold,
  });

  final int chunkSize;
  final int chunkOverlap;
  final int maxFileSizeMb;
  final int retrievalTopK;
  final String retrievalMode;
  final double retrievalSimilarityThreshold;
}

class StorageService {
  StorageService(this._db);

  final DbService _db;
  Future<void>? _encryptionInit;
  encrypt.Key? _encryptionKey;
  String? _encryptionKeyId;

  Future<String> getLocale() async {
    final stored = await _db.getSettings([_storageKeys['locale']!]);
    final storedLocale = stored[_storageKeys['locale']!];
    final systemLocale = getSystemLocale('en');
    return resolveLocale(storedLocale, systemLocale);
  }

  Future<void> setLocale(String? next) async {
    if (next == null || next.isEmpty) {
      await _db.setSetting(_storageKeys['locale']!, null);
      return;
    }
    await _db.setSetting(_storageKeys['locale']!, next);
  }

  Future<AiConfig> getAiConfig() async {
    await _ensureEncryptionKey();
    final stored = await _db.getSettings([
      _storageKeys['aiUrl']!,
      _storageKeys['aiKey']!,
      _storageKeys['aiModel']!,
      _storageKeys['aiModels']!,
      _storageKeys['aiTemperature']!,
      _storageKeys['aiTopP']!,
      _storageKeys['aiMaxTokens']!,
      _storageKeys['aiPresencePenalty']!,
      _storageKeys['aiFrequencyPenalty']!,
    ]);

    final storedUrl = stored[_storageKeys['aiUrl']!];
    final storedKey = await _readEncrypted(stored[_storageKeys['aiKey']!]);
    final storedModel = stored[_storageKeys['aiModel']!];
    final storedModels = stored[_storageKeys['aiModels']!];
    final storedTemperature = stored[_storageKeys['aiTemperature']!];
    final storedTopP = stored[_storageKeys['aiTopP']!];
    final storedMaxTokens = stored[_storageKeys['aiMaxTokens']!];
    final storedPresencePenalty = stored[_storageKeys['aiPresencePenalty']!];
    final storedFrequencyPenalty = stored[_storageKeys['aiFrequencyPenalty']!];
    final resolvedKey = storedKey ?? '';

    final models = _parseModelList(storedModels, storedModel);
    final resolvedModel = _pickDefaultModel(models, storedModel);
    if (storedKey != null) {
      await _rewriteEncryptedIfNeeded(_storageKeys['aiKey']!, storedKey);
    }

    return AiConfig(
      url: storedUrl ?? '',
      apiKey: resolvedKey,
      model: resolvedModel,
      models: models,
      temperature: _parseOptionalDouble(storedTemperature, min: 0, max: 2),
      topP: _parseOptionalDouble(storedTopP, min: 0, max: 1),
      maxTokens: _parseOptionalInt(storedMaxTokens, min: 1),
      presencePenalty: _parseOptionalDouble(storedPresencePenalty, min: -2, max: 2),
      frequencyPenalty: _parseOptionalDouble(storedFrequencyPenalty, min: -2, max: 2),
    );
  }

  Future<void> setAiConfig({
    String? url,
    String? apiKey,
    String? model,
    List<String>? models,
    double? temperature,
    double? topP,
    int? maxTokens,
    double? presencePenalty,
    double? frequencyPenalty,
  }) async {
    if (url != null) {
      final trimmed = url.trim();
      await _db.setSetting(_storageKeys['aiUrl']!, trimmed.isEmpty ? null : trimmed);
    }
    if (apiKey != null) {
      final trimmed = apiKey.trim();
      final stored = trimmed.isEmpty ? null : await _encryptValue(trimmed);
      await _db.setSetting(_storageKeys['aiKey']!, stored);
      if (trimmed.isNotEmpty) {
        await _clearEncryptionKeyLost();
      }
    }
    if (model != null) {
      final trimmed = model.trim();
      await _db.setSetting(_storageKeys['aiModel']!, trimmed.isEmpty ? null : trimmed);
    }
    if (models != null) {
      final normalized = _normalizeModelList(models);
      await _db.setSetting(
        _storageKeys['aiModels']!,
        normalized.isEmpty ? null : _encodeJson(normalized),
      );
      if (model == null) {
        final fallback = normalized.isNotEmpty ? normalized.first : '';
        if (fallback.isNotEmpty) {
          await _db.setSetting(_storageKeys['aiModel']!, fallback);
        }
      }
    }
    if (temperature != null) {
      await _setOptionalNumber(_storageKeys['aiTemperature']!, temperature, min: 0, max: 2);
    }
    if (topP != null) {
      await _setOptionalNumber(_storageKeys['aiTopP']!, topP, min: 0, max: 1);
    }
    if (maxTokens != null) {
      await _setOptionalNumber(_storageKeys['aiMaxTokens']!, maxTokens, min: 1, integer: true);
    }
    if (presencePenalty != null) {
      await _setOptionalNumber(_storageKeys['aiPresencePenalty']!, presencePenalty, min: -2, max: 2);
    }
    if (frequencyPenalty != null) {
      await _setOptionalNumber(_storageKeys['aiFrequencyPenalty']!, frequencyPenalty, min: -2, max: 2);
    }
  }

  Future<EmbeddingConfig> getEmbeddingConfig() async {
    await _ensureEncryptionKey();
    final stored = await _db.getSettings([
      _storageKeys['embeddingUrl']!,
      _storageKeys['embeddingKey']!,
      _storageKeys['embeddingModel']!,
      _storageKeys['embeddingModels']!,
    ]);

    final storedUrl = stored[_storageKeys['embeddingUrl']!];
    final storedKey = await _readEncrypted(stored[_storageKeys['embeddingKey']!]);
    final storedModel = stored[_storageKeys['embeddingModel']!];
    final storedModels = stored[_storageKeys['embeddingModels']!];
    final resolvedKey = storedKey ?? '';

    final models = _parseModelList(storedModels, storedModel);
    final resolvedModel = _pickDefaultModel(models, storedModel);
    if (storedKey != null) {
      await _rewriteEncryptedIfNeeded(_storageKeys['embeddingKey']!, storedKey);
    }

    return EmbeddingConfig(
      url: storedUrl ?? '',
      apiKey: resolvedKey,
      model: resolvedModel,
      models: models,
    );
  }

  Future<void> setEmbeddingConfig({
    String? url,
    String? apiKey,
    String? model,
    List<String>? models,
  }) async {
    if (url != null) {
      final trimmed = url.trim();
      await _db.setSetting(_storageKeys['embeddingUrl']!, trimmed.isEmpty ? null : trimmed);
    }
    if (apiKey != null) {
      final trimmed = apiKey.trim();
      final stored = trimmed.isEmpty ? null : await _encryptValue(trimmed);
      await _db.setSetting(_storageKeys['embeddingKey']!, stored);
      if (trimmed.isNotEmpty) {
        await _clearEncryptionKeyLost();
      }
    }
    if (model != null) {
      final trimmed = model.trim();
      await _db.setSetting(_storageKeys['embeddingModel']!, trimmed.isEmpty ? null : trimmed);
    }
    if (models != null) {
      final normalized = _normalizeModelList(models);
      await _db.setSetting(
        _storageKeys['embeddingModels']!,
        normalized.isEmpty ? null : _encodeJson(normalized),
      );
      if (model == null) {
        final fallback = normalized.isNotEmpty ? normalized.first : '';
        if (fallback.isNotEmpty) {
          await _db.setSetting(_storageKeys['embeddingModel']!, fallback);
        }
      }
    }
  }

  Future<RagConfig> getRagConfig() async {
    final stored = await _db.getSettings([
      _storageKeys['chunkSize']!,
      _storageKeys['chunkOverlap']!,
      _storageKeys['maxFileSizeMb']!,
      _storageKeys['retrievalTopK']!,
      _storageKeys['retrievalMode']!,
      _storageKeys['retrievalSimilarityThreshold']!,
    ]);

    final chunkSize = _parseOptionalInt(stored[_storageKeys['chunkSize']!], min: 1) ?? defaultRagConfig.chunkSize;
    final chunkOverlap =
        _parseOptionalInt(stored[_storageKeys['chunkOverlap']!], min: 0) ?? defaultRagConfig.chunkOverlap;
    final maxFileSize =
        _parseOptionalInt(stored[_storageKeys['maxFileSizeMb']!], min: 1) ?? defaultRagConfig.maxFileSizeMb;
    final retrievalTopK =
        _parseOptionalInt(stored[_storageKeys['retrievalTopK']!], min: 1) ?? defaultRagConfig.retrievalTopK;
    final retrievalMode = stored[_storageKeys['retrievalMode']!] ?? defaultRagConfig.retrievalMode;
    final retrievalSimilarityThreshold = _parseOptionalDouble(
          stored[_storageKeys['retrievalSimilarityThreshold']!],
          min: 0,
          max: 1,
        ) ??
        defaultRagConfig.retrievalSimilarityThreshold;

    return RagConfig(
      chunkSize: chunkSize,
      chunkOverlap: chunkOverlap,
      maxFileSizeMb: maxFileSize,
      retrievalTopK: retrievalTopK,
      retrievalMode: retrievalMode,
      retrievalSimilarityThreshold: retrievalSimilarityThreshold,
    );
  }

  Future<void> setRagConfig({
    int? chunkSize,
    int? chunkOverlap,
    int? maxFileSizeMb,
    int? retrievalTopK,
    String? retrievalMode,
    double? retrievalSimilarityThreshold,
  }) async {
    if (chunkSize != null) {
      await _setOptionalNumber(_storageKeys['chunkSize']!, chunkSize, min: 1, integer: true);
    }
    if (chunkOverlap != null) {
      await _setOptionalNumber(_storageKeys['chunkOverlap']!, chunkOverlap, min: 0, integer: true);
    }
    if (maxFileSizeMb != null) {
      await _setOptionalNumber(_storageKeys['maxFileSizeMb']!, maxFileSizeMb, min: 1, integer: true);
    }
    if (retrievalTopK != null) {
      await _setOptionalNumber(_storageKeys['retrievalTopK']!, retrievalTopK, min: 1, integer: true);
    }
    if (retrievalMode != null) {
      await _db.setSetting(_storageKeys['retrievalMode']!, retrievalMode);
    }
    if (retrievalSimilarityThreshold != null) {
      await _setOptionalNumber(
        _storageKeys['retrievalSimilarityThreshold']!,
        retrievalSimilarityThreshold,
        min: 0,
        max: 1,
      );
    }
  }

  static const _cipherSeparator = ':';

  Future<void> _ensureEncryptionKey() async {
    if (_encryptionKey != null) {
      return;
    }
    _encryptionInit ??= _loadOrCreateEncryptionKey();
    await _encryptionInit;
  }

  Future<encrypt.Encrypter?> _buildEncrypter() async {
    await _ensureEncryptionKey();
    if (_encryptionKey == null) {
      return null;
    }
    return encrypt.Encrypter(encrypt.AES(_encryptionKey!));
  }

  Future<String> _encryptValue(String value) async {
    final encrypter = await _buildEncrypter();
    if (encrypter == null) {
      return value;
    }
    final ivBytes = Uint8List.fromList(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    final iv = encrypt.IV(ivBytes);
    final encrypted = encrypter.encrypt(value, iv: iv);
    return '${base64Encode(iv.bytes)}$_cipherSeparator${encrypted.base64}';
  }

  Future<String?> _readEncrypted(String? stored) async {
    if (stored == null || stored.isEmpty) {
      return stored;
    }
    final encrypter = await _buildEncrypter();
    if (encrypter == null) {
      return null;
    }
    final parts = stored.split(_cipherSeparator);
    if (parts.length != 2) {
      return stored;
    }
    try {
      final iv = encrypt.IV(base64Decode(parts[0]));
      return encrypter.decrypt64(parts[1], iv: iv);
    } catch (_) {
      await _handleEncryptionKeyLost();
      return null;
    }
  }

  Future<void> _rewriteEncryptedIfNeeded(String key, String value) async {
    final encrypted = await _encryptValue(value);
    if (encrypted == value) {
      return;
    }
    await _db.setSetting(key, encrypted);
  }

  Future<void> _loadOrCreateEncryptionKey() async {
    final settings = await _db.getSettings([
      _storageKeys['encryptionKeyId']!,
      _storageKeys['encryptionKeyLost']!,
    ]);
    final storedId = settings[_storageKeys['encryptionKeyId']!];
    final keyFile = await _keyFile();
    if (await keyFile.exists()) {
      final raw = await keyFile.readAsString();
      try {
        final decoded = _decodeJson(raw);
        if (decoded is Map<String, dynamic>) {
          final id = decoded['id']?.toString();
          final key = decoded['key']?.toString();
          if (id != null && key != null && key.isNotEmpty) {
            if (storedId != null && storedId.isNotEmpty && storedId != id) {
              await _handleEncryptionKeyLost();
            }
            _encryptionKeyId = id;
            _encryptionKey = encrypt.Key(base64Decode(key));
            if (storedId == null || storedId.isEmpty) {
              await _db.setSetting(_storageKeys['encryptionKeyId']!, id);
            }
            return;
          }
        }
      } catch (_) {
        // fall through to regenerate
      }
    }

    if (storedId != null && storedId.isNotEmpty) {
      await _handleEncryptionKeyLost();
    }

    final nextId = _generateKeyId();
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    final payload = _encodeJson({
      'id': nextId,
      'key': base64Encode(bytes),
    });
    await keyFile.writeAsString(payload);
    await _db.setSetting(_storageKeys['encryptionKeyId']!, nextId);
    _encryptionKeyId = nextId;
    _encryptionKey = encrypt.Key(bytes);
  }

  Future<File> _keyFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/rag_encryption_key.json');
  }

  String _generateKeyId() {
    final bytes = List<int>.generate(8, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes);
  }

  Future<void> _handleEncryptionKeyLost() async {
    await _db.setSetting(_storageKeys['encryptionKeyLost']!, '1');
    await _db.setSetting(_storageKeys['aiKey']!, null);
    await _db.setSetting(_storageKeys['embeddingKey']!, null);
  }

  Future<void> _clearEncryptionKeyLost() async {
    await _db.setSetting(_storageKeys['encryptionKeyLost']!, null);
  }

  Future<List<PromptTemplate>> getPromptTemplates() async {
    final stored = await _db.getSettings([_storageKeys['promptTemplates']!]);
    final raw = stored[_storageKeys['promptTemplates']!];
    var templates = <PromptTemplate>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = _decodeJson(raw);
        if (decoded is List) {
          templates = decoded
              .whereType<Map<String, dynamic>>()
              .map(PromptTemplate.fromJson)
              .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
              .where((item) => item.id != defaultPromptTemplateId)
              .toList();
        }
      } catch (_) {
        templates = [];
      }
    }
    return [_defaultPromptTemplate, ...templates];
  }

  Future<void> setPromptTemplates(List<PromptTemplate> templates) async {
    final normalized = templates
        .map((item) => PromptTemplate(id: item.id.trim(), title: item.title.trim(), content: item.content))
        .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
        .where((item) => item.id != defaultPromptTemplateId)
        .map((item) => item.toJson())
        .toList();
    await _db.setSetting(
      _storageKeys['promptTemplates']!,
      normalized.isEmpty ? null : _encodeJson(normalized),
    );
  }

  Future<Map<String, String>> getPromptSelections() async {
    final stored = await _db.getSettings([_storageKeys['promptSelections']!]);
    final raw = stored[_storageKeys['promptSelections']!];
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = _decodeJson(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded.map((key, value) => MapEntry(key, value.toString()));
      }
    } catch (_) {
      return {};
    }
    return {};
  }

  Future<void> setPromptSelection(String conversationId, String promptId) async {
    final selections = await getPromptSelections();
    selections[conversationId] = promptId;
    await _db.setSetting(_storageKeys['promptSelections']!, _encodeJson(selections));
  }

  Future<bool> getEncryptionKeyLost() async {
    final stored = await _db.getSettings([_storageKeys['encryptionKeyLost']!]);
    return stored[_storageKeys['encryptionKeyLost']!] == '1';
  }

  List<String> _parseModelList(String? raw, String? fallback) {
    if (raw == null || raw.isEmpty) {
      if (fallback == null || fallback.isEmpty) {
        return [];
      }
      return [fallback];
    }
    try {
      final decoded = _decodeJson(raw);
      if (decoded is List) {
        return decoded.whereType<String>().map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
      }
    } catch (_) {
      return fallback == null || fallback.isEmpty ? [] : [fallback];
    }
    return fallback == null || fallback.isEmpty ? [] : [fallback];
  }

  List<String> _normalizeModelList(List<String> input) {
    return input.map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
  }

  String _pickDefaultModel(List<String> models, String? stored) {
    final trimmed = stored?.trim() ?? '';
    if (trimmed.isNotEmpty && models.contains(trimmed)) {
      return trimmed;
    }
    return models.isNotEmpty ? models.first : trimmed;
  }

  int? _parseOptionalInt(String? value, {required int min}) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < min) {
      return null;
    }
    return parsed;
  }

  double? _parseOptionalDouble(String? value, {required double min, required double max}) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final parsed = double.tryParse(value);
    if (parsed == null || parsed < min || parsed > max) {
      return null;
    }
    return parsed;
  }

  Future<void> _setOptionalNumber(String key, num value, {required num min, num? max, bool integer = false}) async {
    if (value < min) {
      await _db.setSetting(key, null);
      return;
    }
    if (max != null && value > max) {
      await _db.setSetting(key, null);
      return;
    }
    final normalized = integer ? value.round() : value;
    await _db.setSetting(key, normalized.toString());
  }

  String _encodeJson(Object value) {
    return _jsonEncode(value);
  }

  Object? _decodeJson(String raw) {
    return _jsonDecode(raw);
  }
}

String _jsonEncode(Object value) => jsonEncode(value);
Object? _jsonDecode(String raw) => jsonDecode(raw);
