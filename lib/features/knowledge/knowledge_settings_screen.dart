import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/i18n.dart';
import '../../services/api_service.dart';
import '../../utils/chunking.dart';

class KnowledgeSettingsScreen extends ConsumerStatefulWidget {
  const KnowledgeSettingsScreen({super.key, required this.knowledgeBaseId});

  final String knowledgeBaseId;

  @override
  ConsumerState<KnowledgeSettingsScreen> createState() => _KnowledgeSettingsScreenState();
}

class _KnowledgeSettingsScreenState extends ConsumerState<KnowledgeSettingsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  List<String> _embeddingModels = [];
  String _selectedEmbeddingModel = '';
  String _storedEmbeddingModel = '';
  int? _storedChunkMin;
  int? _storedChunkMax;
  int? _storedChunkOverlap;
  String _storedSeparators = '';

  final _chunkMinController = TextEditingController();
  final _chunkMaxController = TextEditingController();
  final _chunkOverlapController = TextEditingController();
  final _separatorsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _chunkMinController.dispose();
    _chunkMaxController.dispose();
    _chunkOverlapController.dispose();
    _separatorsController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final rag = ref.read(ragServiceProvider);
    final embeddingConfig = await ref.read(storageServiceProvider).getEmbeddingConfig();
    final kb = await rag.getKnowledgeBase(widget.knowledgeBaseId);
    if (!mounted) {
      return;
    }
    if (kb == null) {
      setState(() {
        _isLoading = false;
        _error = 'knowledge.detail.notFound';
      });
      return;
    }
    _chunkMinController.text = kb.chunkSizeMin?.toString() ?? '';
    _chunkMaxController.text = kb.chunkSizeMax?.toString() ?? '';
    _chunkOverlapController.text = kb.chunkOverlap?.toString() ?? '';
    _separatorsController.text = kb.chunkSeparators ?? '';
    _embeddingModels = embeddingConfig.models;
    _selectedEmbeddingModel = kb.embeddingModel ?? embeddingConfig.model;
    if (_selectedEmbeddingModel.isEmpty && _embeddingModels.isNotEmpty) {
      _selectedEmbeddingModel = _embeddingModels.first;
    }
    _storedEmbeddingModel = kb.embeddingModel ?? '';
    _storedChunkMin = kb.chunkSizeMin;
    _storedChunkMax = kb.chunkSizeMax;
    _storedChunkOverlap = kb.chunkOverlap;
    _storedSeparators = kb.chunkSeparators ?? '';
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _save() async {
    final locale = ref.read(localeControllerProvider).locale;
    final rag = ref.read(ragServiceProvider);
    final min = int.tryParse(_chunkMinController.text.trim());
    final max = int.tryParse(_chunkMaxController.text.trim());
    final overlap = int.tryParse(_chunkOverlapController.text.trim());
    final nextSeparators = _separatorsController.text.trim();
    final nextEmbeddingModel = _selectedEmbeddingModel;
    if (min != null && max != null && min > max) {
      _showError(translate(locale, 'knowledge.settings.chunking.rangeError'));
      return;
    }

    final hasChanges = min != _storedChunkMin ||
        max != _storedChunkMax ||
        overlap != _storedChunkOverlap ||
        nextSeparators != _storedSeparators ||
        nextEmbeddingModel != _storedEmbeddingModel;
    if (!hasChanges) {
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(translate(locale, 'knowledge.settings.rebuild.notice')),
        content: Text(translate(locale, 'knowledge.settings.rebuild.notice')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(translate(locale, 'common.cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(translate(locale, 'common.confirm')),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    if (nextEmbeddingModel != _storedEmbeddingModel && nextEmbeddingModel.isNotEmpty) {
      final api = ref.read(apiServiceProvider);
      try {
        await api.requestEmbeddings(EmbeddingRequestOptions(input: 'ping', model: nextEmbeddingModel));
      } catch (_) {
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
        }
        _showError(translate(locale, 'knowledge.settings.embeddingInvalid', {'model': nextEmbeddingModel}));
        return;
      }
    }

    await rag.updateKnowledgeBase(
      widget.knowledgeBaseId,
      chunkSizeMin: min,
      chunkSizeMax: max,
      chunkOverlap: overlap,
      chunkSeparators: nextSeparators,
      embeddingModel: nextEmbeddingModel,
    );
    await rag.rebuildKnowledgeBaseChunks(
      knowledgeBaseId: widget.knowledgeBaseId,
      embeddingModel: nextEmbeddingModel,
      chunkSeparators: parseChunkSeparators(nextSeparators),
      chunkSizeMin: min,
      chunkSizeMax: max,
      chunkOverlap: overlap,
    );
    await _load();
    if (mounted) {
      setState(() {
        _isSaving = false;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeControllerProvider).locale;
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(translate(locale, 'knowledge.settings.title'))),
        body: Center(child: Text(translate(locale, _error!))),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(translate(locale, 'knowledge.settings.title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            translate(locale, 'knowledge.settings.chunking'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(translate(locale, 'knowledge.settings.chunking.helper')),
          const SizedBox(height: 12),
          TextField(
            controller: _chunkMinController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: translate(locale, 'knowledge.settings.chunking.min'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _chunkMaxController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: translate(locale, 'knowledge.settings.chunking.max'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _chunkOverlapController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: translate(locale, 'settings.rag.chunkOverlap'),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            translate(locale, 'knowledge.settings.separators.title'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(translate(locale, 'knowledge.settings.separators.helper')),
          const SizedBox(height: 12),
          TextField(
            controller: _separatorsController,
            decoration: InputDecoration(
              hintText: translate(locale, 'knowledge.settings.separators.placeholder'),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            translate(locale, 'knowledge.detail.embedding.label'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (_embeddingModels.isEmpty)
            Text(translate(locale, 'knowledge.detail.embedding.empty'))
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _embeddingModels
                  .map((model) => ChoiceChip(
                        label: Text(model),
                        selected: model == _selectedEmbeddingModel,
                        onSelected: (_) => setState(() => _selectedEmbeddingModel = model),
                      ))
                  .toList(),
            ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 14.4,
                    height: 14.4,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(translate(locale, 'common.save')),
          ),
        ],
      ),
    );
  }
}
