import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/i18n.dart';
import '../../domain/models.dart';

class DocumentChunksScreen extends ConsumerStatefulWidget {
  const DocumentChunksScreen({
    super.key,
    required this.knowledgeBaseId,
    required this.documentId,
  });

  final String knowledgeBaseId;
  final String documentId;

  @override
  ConsumerState<DocumentChunksScreen> createState() => _DocumentChunksScreenState();
}

class _DocumentChunksScreenState extends ConsumerState<DocumentChunksScreen> {
  List<DocumentChunk> _chunks = [];
  Document? _document;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final rag = ref.read(ragServiceProvider);
    final doc = await rag.getDocument(widget.documentId);
    if (doc == null) {
      setState(() {
        _isLoading = false;
        _error = 'knowledge.documentChunks.notFound';
      });
      return;
    }
    final chunks = await rag.listDocumentChunks(widget.documentId);
    if (!mounted) {
      return;
    }
    setState(() {
      _document = doc;
      _chunks = chunks;
      _isLoading = false;
    });
  }

  Future<void> _rebuild() async {
    final locale = ref.read(localeControllerProvider).locale;
    final doc = _document;
    if (doc == null || doc.content == null || doc.content!.isEmpty) {
      _showError(translate(locale, 'knowledge.documentChunks.missingContent'));
      return;
    }
    final rag = ref.read(ragServiceProvider);
    final kb = await rag.getKnowledgeBase(widget.knowledgeBaseId);
    if (kb == null) {
      _showError(translate(locale, 'knowledge.detail.notFound'));
      return;
    }
    final chunkSizeMax = kb.chunkSizeMax ?? (await ref.read(storageServiceProvider).getRagConfig()).chunkSize;
    final chunkSizeMin = kb.chunkSizeMin;
    final chunkOverlap = kb.chunkOverlap ?? (await ref.read(storageServiceProvider).getRagConfig()).chunkOverlap;
    await rag.rebuildDocumentChunks(
      documentId: doc.id,
      content: doc.content!,
      chunkSizeMin: chunkSizeMin,
      chunkSizeMax: chunkSizeMax,
      chunkOverlap: chunkOverlap,
      embeddingModel: kb.embeddingModel,
      chunkSeparators: null,
    );
    await _load();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeControllerProvider).locale;

    return Scaffold(
      appBar: AppBar(
        title: Text(translate(locale, 'knowledge.documentChunks.title')),
        actions: [
          IconButton(
            onPressed: _rebuild,
            icon: const Icon(Icons.refresh),
            tooltip: translate(locale, 'knowledge.documentChunks.rebuild'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(translate(locale, _error!)))
              : _chunks.isEmpty
                  ? Center(child: Text(translate(locale, 'knowledge.documentChunks.empty')))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _chunks.length,
                      itemBuilder: (context, index) {
                        final chunk = _chunks[index];
                        return Card(
                          child: ListTile(
                            title: Text(translate(locale, 'knowledge.documentChunks.chunkTitle', {'index': index + 1})),
                            subtitle: Text(chunk.content),
                          ),
                        );
                      },
                    ),
    );
  }
}
