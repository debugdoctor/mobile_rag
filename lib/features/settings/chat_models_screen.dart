import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/i18n.dart';
import '../../services/api_service.dart';

class ChatModelsScreen extends ConsumerStatefulWidget {
  const ChatModelsScreen({super.key});

  @override
  ConsumerState<ChatModelsScreen> createState() => _ChatModelsScreenState();
}

class _ChatModelsScreenState extends ConsumerState<ChatModelsScreen> {
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  final _modelController = TextEditingController();
  Timer? _debounce;
  String _activeModel = '';
  List<String> _models = [];
  final Map<String, _TestState> _tests = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _urlController.dispose();
    _keyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final storage = ref.read(storageServiceProvider);
    final config = await storage.getAiConfig();
    if (!mounted) {
      return;
    }
    setState(() {
      _urlController.text = config.url;
      _keyController.text = config.apiKey;
      _models = config.models;
      _activeModel = config.model;
    });
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final storage = ref.read(storageServiceProvider);
      setState(() {
        _error = null;
      });
      try {
        await storage.setAiConfig(
          url: _urlController.text.trim(),
          apiKey: _keyController.text.trim(),
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        setState(() {
          _error = error.toString();
        });
      }
    });
  }

  Future<void> _addModel() async {
    final trimmed = _modelController.text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    if (_models.contains(trimmed)) {
      setState(() {
        _modelController.clear();
      });
      return;
    }
    final next = [..._models, trimmed];
    await _updateModels(next, trimmed);
    setState(() {
      _modelController.clear();
    });
  }

  Future<void> _updateModels(List<String> next, String? selected) async {
    final storage = ref.read(storageServiceProvider);
    await storage.setAiConfig(models: next, model: selected ?? _activeModel);
    await _load();
  }

  Future<void> _removeModel(String id) async {
    final next = _models.where((item) => item != id).toList();
    final nextSelected = _activeModel == id ? '' : _activeModel;
    await _updateModels(next, nextSelected);
  }

  Future<void> _selectModel(String id) async {
    await _updateModels(_models, id);
  }

  Future<void> _testModel(String id) async {
    final locale = ref.read(localeControllerProvider).locale;
    setState(() {
      _tests[id] = _TestState(isTesting: true);
    });
    try {
      final storage = ref.read(storageServiceProvider);
      await storage.setAiConfig(
        url: _urlController.text.trim(),
        apiKey: _keyController.text.trim(),
      );
      final api = ref.read(apiServiceProvider);
      await api.requestAiAnswer(
        AiRequestOptions(
          messages: [
            AiMessage(role: 'system', content: 'ping'),
            AiMessage(role: 'user', content: 'ping'),
          ],
          model: id,
        ),
      );
      setState(() {
        _tests[id] = _TestState(isTesting: false, message: translate(locale, 'settings.models.testSuccess'));
      });
    } catch (error) {
      setState(() {
        _tests[id] = _TestState(isTesting: false, message: error.toString(), isError: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeControllerProvider).locale;
    final palette = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(translate(locale, 'settings.chat.title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(translate(locale, 'settings.models.chatDesc')),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(translate(locale, 'settings.chat.connection')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _urlController,
                    decoration: InputDecoration(hintText: translate(locale, 'settings.placeholder.baseUrl')),
                    onChanged: (_) => _scheduleSave(),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _keyController,
                    decoration: InputDecoration(hintText: translate(locale, 'settings.placeholder.apiKey')),
                    onChanged: (_) => _scheduleSave(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: palette.error)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(translate(locale, 'settings.models.idsTitle')),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _modelController,
                          decoration: InputDecoration(
                            hintText: translate(locale, 'settings.models.idPlaceholder'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _addModel,
                        child: Text(translate(locale, 'settings.models.add')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_models.isEmpty)
                    Text(translate(locale, 'settings.models.empty'))
                  else
                    ..._models.map((item) {
                      final isActive = item == _activeModel;
                      final test = _tests[item];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          title: Text(item),
                          selected: isActive,
                          subtitle: test?.message != null
                              ? Text(
                                  test!.message!,
                                  style: TextStyle(color: test.isError ? palette.error : palette.primary),
                                )
                              : null,
                          onTap: () => _selectModel(item),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: test?.isTesting == true ? null : () => _testModel(item),
                                child: test?.isTesting == true
                                    ? Text(translate(locale, 'settings.models.testing'))
                                    : Text(translate(locale, 'settings.models.test')),
                              ),
                              IconButton(
                                onPressed: () => _removeModel(item),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TestState {
  _TestState({required this.isTesting, this.message, this.isError = false});

  final bool isTesting;
  final String? message;
  final bool isError;
}
