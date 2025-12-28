import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_providers.dart';
import '../../core/i18n.dart';
import '../../domain/models.dart';
import '../../services/rag_service.dart';
import '../../utils/chunking.dart';

class KnowledgeDetailScreen extends ConsumerStatefulWidget {
  const KnowledgeDetailScreen({super.key, required this.knowledgeBaseId});

  final String knowledgeBaseId;

  @override
  ConsumerState<KnowledgeDetailScreen> createState() => _KnowledgeDetailScreenState();
}

class _KnowledgeDetailScreenState extends ConsumerState<KnowledgeDetailScreen> {
  KnowledgeBase? _knowledgeBase;
  List<Document> _documents = [];
  bool _isLoading = true;
  bool _isUploading = false;
  String? _error;
  EmbeddingProgress? _progress;

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
    final kb = await rag.getKnowledgeBase(widget.knowledgeBaseId);
    if (kb == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = 'knowledge.detail.notFound';
      });
      return;
    }
    final docs = await rag.listDocuments(widget.knowledgeBaseId);
    if (!mounted) {
      return;
    }
    setState(() {
      _knowledgeBase = kb;
      _documents = docs;
      _isLoading = false;
    });
  }

  Future<void> _uploadFile({Document? replaceTarget}) async {
    final locale = ref.read(localeControllerProvider).locale;
    final rag = ref.read(ragServiceProvider);
    final kb = _knowledgeBase;
    if (kb == null) {
      return;
    }
    setState(() {
      _isUploading = true;
      _error = null;
      _progress = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt', 'md'],
        withData: true,
        allowMultiple: replaceTarget == null,
      );
      if (result == null || result.files.isEmpty) {
        setState(() {
          _isUploading = false;
          _progress = null;
        });
        return;
      }
      for (final file in result.files) {
        final name = file.name;
        if (!(name.endsWith('.txt') || name.endsWith('.md'))) {
          _showError(translate(locale, 'file.unsupportedType'));
          continue;
        }
        if (kb.maxFileSizeMb != null && file.size > kb.maxFileSizeMb! * 1024 * 1024) {
          _showError(translate(locale, 'file.tooLarge', {'size': kb.maxFileSizeMb!}));
          continue;
        }

        final bytes = file.bytes ?? await File(file.path!).readAsBytes();
        final content = utf8.decode(bytes).trim();
        if (content.isEmpty) {
          _showError(translate(locale, 'file.empty'));
          continue;
        }

        final chunkSizeMax = kb.chunkSizeMax ?? (await ref.read(storageServiceProvider).getRagConfig()).chunkSize;
        final chunkSizeMin = kb.chunkSizeMin;
        final chunkOverlap = kb.chunkOverlap ?? (await ref.read(storageServiceProvider).getRagConfig()).chunkOverlap;

        if (replaceTarget == null) {
          await rag.createDocument(
            knowledgeBaseId: kb.id,
            title: file.name,
            content: content,
            chunkSizeMin: chunkSizeMin,
            chunkSizeMax: chunkSizeMax,
            chunkOverlap: chunkOverlap,
            embeddingModel: kb.embeddingModel,
            chunkSeparators: parseChunkSeparators(kb.chunkSeparators),
            onProgress: (progress) {
              setState(() {
                _progress = progress;
              });
            },
          );
        } else {
          await rag.updateDocument(
            documentId: replaceTarget.id,
            title: replaceTarget.title,
            content: content,
            chunkSizeMin: chunkSizeMin,
            chunkSizeMax: chunkSizeMax,
            chunkOverlap: chunkOverlap,
            embeddingModel: kb.embeddingModel,
            chunkSeparators: parseChunkSeparators(kb.chunkSeparators),
            onProgress: (progress) {
              setState(() {
                _progress = progress;
              });
            },
          );
        }
      }
      await _load();
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _renameDocument(Document doc) async {
    final locale = ref.read(localeControllerProvider).locale;
    final controller = TextEditingController(text: doc.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(translate(locale, 'knowledge.detail.rename.title')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: translate(locale, 'knowledge.detail.rename.placeholder'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(translate(locale, 'common.cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(translate(locale, 'common.save')),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final title = controller.text.trim();
    if (title.isEmpty) {
      _showError(translate(locale, 'knowledge.detail.rename.required'));
      return;
    }
    await ref.read(ragServiceProvider).updateDocument(documentId: doc.id, title: title);
    await _load();
  }

  Future<void> _deleteDocument(Document doc) async {
    final locale = ref.read(localeControllerProvider).locale;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(translate(locale, 'knowledge.detail.deleteTitle')),
        content: Text(translate(locale, 'knowledge.detail.deleteMessage', {'title': doc.title})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(translate(locale, 'common.cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: Text(translate(locale, 'common.delete')),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    await ref.read(ragServiceProvider).deleteDocument(doc.id);
    await _load();
  }

  Future<void> _clearAll() async {
    final locale = ref.read(localeControllerProvider).locale;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(translate(locale, 'knowledge.detail.clearAllTitle')),
        content: Text(translate(locale, 'knowledge.detail.clearAllMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(translate(locale, 'common.cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: Text(translate(locale, 'common.delete')),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    await ref.read(ragServiceProvider).clearKnowledgeBaseDocuments(widget.knowledgeBaseId);
    await _load();
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeControllerProvider).locale;
    final kb = _knowledgeBase;

    return Scaffold(
      appBar: AppBar(
        title: Text(translate(locale, 'knowledge.detail.title')),
        actions: [
          if (kb != null)
            IconButton(
              onPressed: () => context.go('/knowledge/${kb.id}/settings'),
              icon: const Icon(Icons.tune),
              tooltip: translate(locale, 'knowledge.settings.title'),
            ),
          IconButton(
            onPressed: _clearAll,
            icon: const Icon(Icons.delete_outline),
            tooltip: translate(locale, 'knowledge.detail.clearAll'),
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isUploading ? null : () => _uploadFile(),
        child: _isUploading ? const CircularProgressIndicator() : const Icon(Icons.upload_file),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : kb == null
              ? Center(child: Text(translate(locale, _error ?? 'knowledge.detail.notFound')))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      kb.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    if (kb.description?.isNotEmpty == true)
                      Text(kb.description!),
                    const SizedBox(height: 16),
                    if (_progress != null)
                      _EmbeddingProgressCard(progress: _progress!, locale: locale),
                    if (_documents.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(translate(locale, 'knowledge.detail.empty')),
                      )
                    else
                      ..._documents.map(
                        (doc) => Card(
                          child: ListTile(
                            title: Text(doc.title),
                            subtitle: Text(
                              translate(locale, 'knowledge.detail.updated', {'date': formatDate(doc.updatedAt, locale)}),
                            ),
                            onTap: () => context.go('/knowledge/${kb.id}/chunks/${doc.id}'),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                switch (value) {
                                  case 'rename':
                                    _renameDocument(doc);
                                    break;
                                  case 'replace':
                                    _uploadFile(replaceTarget: doc);
                                    break;
                                  case 'delete':
                                    _deleteDocument(doc);
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text(translate(locale, 'knowledge.detail.rename')),
                                ),
                                PopupMenuItem(
                                  value: 'replace',
                                  child: Text(translate(locale, 'knowledge.detail.replace')),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(translate(locale, 'knowledge.delete')),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }
}

class _EmbeddingProgressCard extends StatelessWidget {
  const _EmbeddingProgressCard({required this.progress, required this.locale});

  final EmbeddingProgress progress;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final stageLabel = switch (progress.stage) {
      'chunking' => translate(locale, 'knowledge.detail.embedding.chunking'),
      'embedding' => translate(locale, 'knowledge.detail.embedding.embedding'),
      'saving' => translate(locale, 'knowledge.detail.embedding.saving'),
      _ => translate(locale, 'common.loading'),
    };

    final total = progress.total ?? 0;
    final current = progress.current ?? 0;
    final ratio = total > 0 ? current / total : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(stageLabel),
            if (ratio != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: ratio),
              const SizedBox(height: 8),
              Text(translate(locale, 'knowledge.detail.embedding.progress', {'current': current, 'total': total})),
            ] else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
