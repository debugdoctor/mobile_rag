import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/i18n.dart';
import '../../domain/models.dart';
import '../../utils/ids.dart';

class PromptTemplatesScreen extends ConsumerStatefulWidget {
  const PromptTemplatesScreen({super.key});

  @override
  ConsumerState<PromptTemplatesScreen> createState() => _PromptTemplatesScreenState();
}

class _PromptTemplatesScreenState extends ConsumerState<PromptTemplatesScreen> {
  bool _loading = true;
  List<PromptTemplate> _templates = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final storage = ref.read(storageServiceProvider);
    final templates = await storage.getPromptTemplates();
    if (!mounted) {
      return;
    }
    setState(() {
      _templates = templates;
      _loading = false;
    });
  }

  Future<void> _saveTemplates(List<PromptTemplate> next) async {
    await ref.read(storageServiceProvider).setPromptTemplates(next);
    if (!mounted) {
      return;
    }
    setState(() {
      _templates = next;
    });
  }

  Future<void> _upsertTemplate({PromptTemplate? template}) async {
    final locale = ref.read(localeControllerProvider).locale;
    if (template?.id == defaultPromptTemplateId) {
      _showMessage(translate(locale, 'settings.prompt.defaultLocked'));
      return;
    }
    final titleController = TextEditingController(text: template?.title ?? '');
    final contentController = TextEditingController(text: template?.content ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          template == null
              ? translate(locale, 'settings.prompt.addTitle')
              : translate(locale, 'settings.prompt.editTitle'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: translate(locale, 'settings.prompt.titleLabel'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contentController,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: translate(locale, 'settings.prompt.content'),
                hintText: translate(locale, 'settings.prompt.placeholder'),
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
      ),
    );

    if (ok != true) {
      return;
    }

    final title = titleController.text.trim();
    final content = contentController.text.trim();
    if (title.isEmpty || content.isEmpty) {
      _showMessage(translate(locale, 'settings.prompt.required'));
      return;
    }
    if (template == null) {
      final next = [
        ..._templates,
        PromptTemplate(id: createId('prompt'), title: title, content: content),
      ];
      await _saveTemplates(next);
    } else {
      final next = _templates
          .map((item) => item.id == template.id
              ? PromptTemplate(id: template.id, title: title, content: content)
              : item)
          .toList();
      await _saveTemplates(next);
    }
  }

  Future<void> _deleteTemplate(PromptTemplate template) async {
    final locale = ref.read(localeControllerProvider).locale;
    if (template.id == defaultPromptTemplateId) {
      _showMessage(translate(locale, 'settings.prompt.defaultLocked'));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(translate(locale, 'settings.prompt.deleteTitle')),
        content: Text(translate(locale, 'settings.prompt.deleteMessage', {'title': template.title})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(translate(locale, 'common.cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(translate(locale, 'common.delete')),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final next = _templates.where((item) => item.id != template.id).toList();
    await _saveTemplates(next);
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeControllerProvider).locale;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(translate(locale, 'settings.prompt.title')),
        actions: [
          IconButton(
            onPressed: () => _upsertTemplate(),
            icon: const Icon(Icons.add),
            tooltip: translate(locale, 'settings.prompt.add'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_templates.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(translate(locale, 'settings.prompt.empty')),
            )
          else
            ..._templates.map(
              (template) => Card(
                child: ListTile(
                  title: Text(_displayTitle(locale, template)),
                  subtitle: Text(
                    _templatePreview(locale, template),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: template.id == defaultPromptTemplateId ? null : () => _upsertTemplate(template: template),
                  trailing: IconButton(
                    onPressed: template.id == defaultPromptTemplateId ? null : () => _deleteTemplate(template),
                    icon: Icon(
                      template.id == defaultPromptTemplateId ? Icons.lock_outline : Icons.delete_outline,
                    ),
                    tooltip: template.id == defaultPromptTemplateId
                        ? translate(locale, 'settings.prompt.defaultLocked')
                        : translate(locale, 'common.delete'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _displayTitle(String locale, PromptTemplate template) {
    if (template.id == defaultPromptTemplateId) {
      return translate(locale, 'settings.prompt.defaultTitle');
    }
    return template.title;
  }

  String _templatePreview(String locale, PromptTemplate template) {
    if (template.id == defaultPromptTemplateId) {
      return translate(locale, 'prompt.system');
    }
    return template.content;
  }

}
