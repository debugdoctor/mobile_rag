import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_providers.dart';
import '../../core/i18n.dart';
import '../../domain/models.dart';

class KnowledgeScreen extends ConsumerStatefulWidget {
  const KnowledgeScreen({super.key});

  @override
  ConsumerState<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends ConsumerState<KnowledgeScreen> {
  final _searchController = TextEditingController();
  List<KnowledgeBase> _knowledgeBases = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
    });
    final rag = ref.read(ragServiceProvider);
    final data = await rag.listKnowledgeBases();
    if (!mounted) {
      return;
    }
    setState(() {
      _knowledgeBases = data;
      _isLoading = false;
    });
  }

  Future<void> _createKnowledgeBase() async {
    final locale = ref.read(localeControllerProvider).locale;
    final controller = TextEditingController();
    final descController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(translate(locale, 'knowledge.form.createTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: translate(locale, 'knowledge.form.namePlaceholder'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: InputDecoration(
                  hintText: translate(locale, 'knowledge.form.descriptionPlaceholder'),
                ),
              ),
            ],
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
        );
      },
    );

    if (result != true) {
      return;
    }
    final name = controller.text.trim();
    if (name.isEmpty) {
      _showError(translate(locale, 'knowledge.form.nameRequired'));
      return;
    }
    final rag = ref.read(ragServiceProvider);
    await rag.createKnowledgeBase(name, description: descController.text.trim());
    await _load();
  }

  Future<void> _editKnowledgeBase(KnowledgeBase kb) async {
    final locale = ref.read(localeControllerProvider).locale;
    final controller = TextEditingController(text: kb.name);
    final descController = TextEditingController(text: kb.description ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(translate(locale, 'knowledge.form.editTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: translate(locale, 'knowledge.form.namePlaceholder'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: InputDecoration(
                  hintText: translate(locale, 'knowledge.form.descriptionPlaceholder'),
                ),
              ),
            ],
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
        );
      },
    );

    if (result != true) {
      return;
    }
    final name = controller.text.trim();
    if (name.isEmpty) {
      _showError(translate(locale, 'knowledge.form.nameRequired'));
      return;
    }
    final rag = ref.read(ragServiceProvider);
    await rag.updateKnowledgeBase(kb.id, name: name, description: descController.text.trim());
    await _load();
  }

  Future<void> _deleteKnowledgeBase(KnowledgeBase kb) async {
    final locale = ref.read(localeControllerProvider).locale;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(translate(locale, 'knowledge.delete.title')),
          content: Text(translate(locale, 'knowledge.delete.message', {'name': kb.name})),
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
        );
      },
    );

    if (result != true) {
      return;
    }
    final rag = ref.read(ragServiceProvider);
    await rag.deleteKnowledgeBase(kb.id);
    await _load();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeControllerProvider).locale;
    final query = _searchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _knowledgeBases
        : _knowledgeBases.where((kb) => kb.name.toLowerCase().contains(query)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(translate(locale, 'knowledge.title')),
        actions: [
          IconButton(
            onPressed: _createKnowledgeBase,
            icon: const Icon(Icons.add),
            tooltip: translate(locale, 'knowledge.create'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: translate(locale, 'knowledge.search.placeholder'),
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (filtered.isEmpty)
              Center(child: Text(translate(locale, 'knowledge.empty')))
            else
              ...filtered.map(
                (kb) => Card(
                  child: ListTile(
                    title: Text(kb.name),
                    subtitle: Text(
                      kb.description?.isNotEmpty == true
                          ? kb.description!
                          : translate(locale, 'knowledge.subtitle'),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            _editKnowledgeBase(kb);
                            break;
                          case 'settings':
                            context.go('/knowledge/${kb.id}/settings');
                            break;
                          case 'delete':
                            _deleteKnowledgeBase(kb);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(translate(locale, 'knowledge.edit')),
                        ),
                        PopupMenuItem(
                          value: 'settings',
                          child: Text(translate(locale, 'knowledge.settings')),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(translate(locale, 'knowledge.delete')),
                        ),
                      ],
                    ),
                    onTap: () => context.go('/knowledge/${kb.id}'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
