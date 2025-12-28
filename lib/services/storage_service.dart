import 'dart:convert';

import '../core/i18n.dart';
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
  'chunkSize': 'rag.config.chunkSize',
  'chunkOverlap': 'rag.config.chunkOverlap',
  'maxFileSizeMb': 'rag.config.maxFileSizeMb',
  'retrievalTopK': 'rag.config.retrievalTopK',
  'retrievalMode': 'rag.config.retrievalMode',
};

const defaultRagConfig = RagConfig(
  chunkSize: 800,
  chunkOverlap: 120,
  maxFileSizeMb: 5,
  retrievalTopK: 12,
  retrievalMode: 'hybrid',
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
  });

  final int chunkSize;
  final int chunkOverlap;
  final int maxFileSizeMb;
  final int retrievalTopK;
  final String retrievalMode;
}

class StorageService {
  StorageService(this._db);

  final DbService _db;

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
    final storedKey = stored[_storageKeys['aiKey']!];
    final storedModel = stored[_storageKeys['aiModel']!];
    final storedModels = stored[_storageKeys['aiModels']!];
    final storedTemperature = stored[_storageKeys['aiTemperature']!];
    final storedTopP = stored[_storageKeys['aiTopP']!];
    final storedMaxTokens = stored[_storageKeys['aiMaxTokens']!];
    final storedPresencePenalty = stored[_storageKeys['aiPresencePenalty']!];
    final storedFrequencyPenalty = stored[_storageKeys['aiFrequencyPenalty']!];

    final models = _parseModelList(storedModels, storedModel);
    final resolvedModel = _pickDefaultModel(models, storedModel);

    return AiConfig(
      url: storedUrl ?? '',
      apiKey: storedKey ?? '',
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
      await _db.setSetting(_storageKeys['aiKey']!, trimmed.isEmpty ? null : trimmed);
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
    final stored = await _db.getSettings([
      _storageKeys['embeddingUrl']!,
      _storageKeys['embeddingKey']!,
      _storageKeys['embeddingModel']!,
      _storageKeys['embeddingModels']!,
    ]);

    final storedUrl = stored[_storageKeys['embeddingUrl']!];
    final storedKey = stored[_storageKeys['embeddingKey']!];
    final storedModel = stored[_storageKeys['embeddingModel']!];
    final storedModels = stored[_storageKeys['embeddingModels']!];

    final models = _parseModelList(storedModels, storedModel);
    final resolvedModel = _pickDefaultModel(models, storedModel);

    return EmbeddingConfig(
      url: storedUrl ?? '',
      apiKey: storedKey ?? '',
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
      await _db.setSetting(_storageKeys['embeddingKey']!, trimmed.isEmpty ? null : trimmed);
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
    ]);

    final chunkSize = _parseOptionalInt(stored[_storageKeys['chunkSize']!], min: 1) ?? defaultRagConfig.chunkSize;
    final chunkOverlap =
        _parseOptionalInt(stored[_storageKeys['chunkOverlap']!], min: 0) ?? defaultRagConfig.chunkOverlap;
    final maxFileSize =
        _parseOptionalInt(stored[_storageKeys['maxFileSizeMb']!], min: 1) ?? defaultRagConfig.maxFileSizeMb;
    final retrievalTopK =
        _parseOptionalInt(stored[_storageKeys['retrievalTopK']!], min: 1) ?? defaultRagConfig.retrievalTopK;
    final retrievalMode = stored[_storageKeys['retrievalMode']!] ?? defaultRagConfig.retrievalMode;

    return RagConfig(
      chunkSize: chunkSize,
      chunkOverlap: chunkOverlap,
      maxFileSizeMb: maxFileSize,
      retrievalTopK: retrievalTopK,
      retrievalMode: retrievalMode,
    );
  }

  Future<void> setRagConfig({
    int? chunkSize,
    int? chunkOverlap,
    int? maxFileSizeMb,
    int? retrievalTopK,
    String? retrievalMode,
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
