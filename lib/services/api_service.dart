import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/i18n.dart';
import 'storage_service.dart';

class AiMessage {
  AiMessage({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class AiRequestOptions {
  AiRequestOptions({
    required this.messages,
    this.model,
    this.temperature,
    this.topP,
    this.maxTokens,
    this.presencePenalty,
    this.frequencyPenalty,
  });

  final List<AiMessage> messages;
  final String? model;
  final double? temperature;
  final double? topP;
  final int? maxTokens;
  final double? presencePenalty;
  final double? frequencyPenalty;
}

class EmbeddingRequestOptions {
  EmbeddingRequestOptions({required this.input, this.model});

  final Object input;
  final String? model;
}

class ApiService {
  ApiService(this._storage, [Dio? dio]) : _dio = dio ?? Dio();

  final StorageService _storage;
  final Dio _dio;

  Future<String> requestAiAnswer(AiRequestOptions options) async {
    final locale = await _storage.getLocale();
    final config = await _storage.getAiConfig();
    if (config.url.isEmpty) {
      throw StateError(translate(locale, 'error.missingAiUrl'));
    }
    final model = _pickModel(options.model, config.model);
    if (model.isEmpty) {
      throw StateError(translate(locale, 'error.missingChatModel'));
    }

    final headers = _buildHeaders(config.apiKey, accept: 'application/json');
    final url = '${config.url.replaceAll(RegExp(r'/*$'), '')}/chat/completions';
    final payload = _buildChatPayload(options, config, stream: false, model: model);

    final response = await _dio.post(
      url,
      data: payload,
      options: Options(headers: headers, responseType: ResponseType.json),
    );

    if (response.statusCode == null || response.statusCode! >= 300) {
      throw StateError(_parseError(response, locale));
    }
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return _extractText(data, locale);
    }
    if (data is String) {
      return data;
    }
    return _extractText({}, locale);
  }

  Future<String> requestAiAnswerStream(
    AiRequestOptions options,
    void Function(String chunk) onChunk,
  ) async {
    final locale = await _storage.getLocale();
    final config = await _storage.getAiConfig();
    if (config.url.isEmpty) {
      throw StateError(translate(locale, 'error.missingAiUrl'));
    }
    final model = _pickModel(options.model, config.model);
    if (model.isEmpty) {
      throw StateError(translate(locale, 'error.missingChatModel'));
    }

    final headers = _buildHeaders(config.apiKey, accept: 'text/event-stream');
    final url = '${config.url.replaceAll(RegExp(r'/*$'), '')}/chat/completions';
    final payload = _buildChatPayload(options, config, stream: true, model: model);

    final response = await _dio.post<ResponseBody>(
      url,
      data: payload,
      options: Options(
        headers: headers,
        responseType: ResponseType.stream,
      ),
    );

    if (response.statusCode == null || response.statusCode! >= 300) {
      throw StateError(_parseError(response, locale));
    }

    final body = response.data;
    if (body == null) {
      throw StateError(translate(locale, 'error.streamUnavailable'));
    }

    final stream = body.stream.transform(
      StreamTransformer<Uint8List, String>.fromHandlers(
        handleData: (data, sink) => sink.add(utf8.decode(data)),
      ),
    );
    var buffer = '';
    var fullContent = '';

    await for (final chunk in stream) {
      buffer += chunk;
      var newlineIndex = buffer.indexOf('\n');
      while (newlineIndex != -1) {
        final rawLine = buffer.substring(0, newlineIndex).trim();
        buffer = buffer.substring(newlineIndex + 1);
        final done = _handleStreamLine(rawLine, onChunk, (value) => fullContent += value);
        if (done) {
          return fullContent;
        }
        newlineIndex = buffer.indexOf('\n');
      }
    }

    final remaining = buffer.trim();
    if (_handleStreamLine(remaining, onChunk, (value) => fullContent += value)) {
      return fullContent;
    }
    return fullContent;
  }

  Future<List<List<double>>> requestEmbeddings(EmbeddingRequestOptions options) async {
    final locale = await _storage.getLocale();
    final config = await _storage.getEmbeddingConfig();
    if (config.url.isEmpty) {
      throw StateError(translate(locale, 'error.missingEmbeddingUrl'));
    }
    final model = _pickModel(options.model, config.model);
    if (model.isEmpty) {
      throw StateError(translate(locale, 'error.missingEmbeddingModel'));
    }

    final headers = _buildHeaders(config.apiKey, accept: 'application/json');
    final url = '${config.url.replaceAll(RegExp(r'/*$'), '')}/embeddings';

    final payload = {
      'model': model,
      'input': options.input,
    };

    final response = await _dio.post(
      url,
      data: payload,
      options: Options(headers: headers, responseType: ResponseType.json),
    );

    if (response.statusCode == null || response.statusCode! >= 300) {
      throw StateError(_parseError(response, locale));
    }

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw StateError(translate(locale, 'error.embeddingResponseNonJson'));
    }

    if (data['data'] is List) {
      final list = List<Map<String, dynamic>>.from(data['data'] as List);
      final sorted = list
          .map((item) => item)
          .where((item) => item['embedding'] is List)
          .toList()
        ..sort((a, b) => (a['index'] ?? 0).compareTo(b['index'] ?? 0));
      final embeddings = sorted
          .map((item) => (item['embedding'] as List).map((v) => (v as num).toDouble()).toList())
          .toList();
      if (embeddings.isNotEmpty) {
        return embeddings;
      }
    }

    if (data['embedding'] is List) {
      return [
        (data['embedding'] as List).map((v) => (v as num).toDouble()).toList(),
      ];
    }

    if (data['embeddings'] is List) {
      final embeddings = (data['embeddings'] as List)
          .map((item) => (item as List).map((v) => (v as num).toDouble()).toList())
          .toList();
      if (embeddings.isNotEmpty) {
        return embeddings;
      }
    }

    throw StateError(translate(locale, 'error.embeddingResponseInvalid'));
  }

  Future<List<double>> requestEmbedding(EmbeddingRequestOptions options) async {
    final embeddings = await requestEmbeddings(options);
    if (embeddings.isEmpty) {
      final locale = await _storage.getLocale();
      throw StateError(translate(locale, 'error.embeddingResponseInvalid'));
    }
    return embeddings.first;
  }

  String _pickModel(String? override, String configured) {
    final normalizedOverride = override?.trim();
    if (normalizedOverride != null && normalizedOverride.isNotEmpty) {
      return normalizedOverride;
    }
    final normalizedConfigured = configured.trim();
    return normalizedConfigured;
  }

  Map<String, dynamic> _buildChatPayload(
    AiRequestOptions options,
    AiConfig config, {
    required bool stream,
    required String model,
  }) {
    final temperature = options.temperature ?? config.temperature ?? 0.2;
    final topP = options.topP ?? config.topP;
    final maxTokens = options.maxTokens ?? config.maxTokens;
    final presencePenalty = options.presencePenalty ?? config.presencePenalty;
    final frequencyPenalty = options.frequencyPenalty ?? config.frequencyPenalty;

    final payload = <String, dynamic>{
      'model': model,
      'messages': options.messages.map((item) => item.toJson()).toList(),
      'temperature': temperature,
      'stream': stream,
    };

    if (topP != null) {
      payload['top_p'] = topP;
    }
    if (maxTokens != null) {
      payload['max_tokens'] = maxTokens;
    }
    if (presencePenalty != null) {
      payload['presence_penalty'] = presencePenalty;
    }
    if (frequencyPenalty != null) {
      payload['frequency_penalty'] = frequencyPenalty;
    }

    return payload;
  }

  Map<String, String> _buildHeaders(String apiKey, {required String accept}) {
    final headers = <String, String>{
      'Accept': accept,
      'Content-Type': 'application/json',
    };
    if (apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    return headers;
  }

  bool _handleStreamLine(
    String line,
    void Function(String chunk) onChunk,
    void Function(String chunk) onFull,
  ) {
    if (line.isEmpty || !line.startsWith('data:')) {
      return false;
    }
    final data = line.replaceFirst(RegExp(r'^data:\s*'), '');
    if (data.isEmpty) {
      return false;
    }
    if (data == '[DONE]') {
      return true;
    }
    try {
      final parsed = jsonDecode(data);
      if (parsed is Map<String, dynamic>) {
        final choices = parsed['choices'];
        if (choices is List && choices.isNotEmpty) {
          final choice = choices.first as Map<String, dynamic>;
          final delta = choice['delta'] as Map<String, dynamic>?;
          final content = delta?['content'] ?? choice['message']?['content'];
          if (content is String && content.isNotEmpty) {
            onFull(content);
            onChunk(content);
          }
        }
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  String _extractText(Map<String, dynamic> data, String locale) {
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      final choice = choices.first;
      if (choice is Map<String, dynamic>) {
        final message = choice['message'];
        if (message is Map<String, dynamic> && message['content'] is String) {
          return message['content'] as String;
        }
        if (choice['text'] is String) {
          return choice['text'] as String;
        }
      }
    }
    if (data['answer'] is String) {
      return data['answer'] as String;
    }
    if (data['content'] is String) {
      return data['content'] as String;
    }
    if (data['message'] is String) {
      return data['message'] as String;
    }
    throw StateError(translate(locale, 'error.aiResponseInvalid'));
  }

  String _parseError(Response response, String locale) {
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data['message']?.toString() ??
          data['error']?.toString() ??
          translate(locale, 'error.requestFailed', {'status': response.statusCode ?? 0});
    }
    if (data is String && data.isNotEmpty) {
      return data;
    }
    return translate(locale, 'error.requestFailed', {'status': response.statusCode ?? 0});
  }
}
