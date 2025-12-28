import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_providers.dart';
import '../../core/i18n.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _loading = true;
  String _localeDraft = 'en';
  String _retrievalTopKDraft = '';
  String _retrievalModeDraft = 'hybrid';
  String? _localeError;
  String? _retrievalError;
  Timer? _localeDebounce;
  Timer? _retrievalDebounce;
  Timer? _modeDebounce;
  final _retrievalTopKController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _localeDebounce?.cancel();
    _retrievalDebounce?.cancel();
    _modeDebounce?.cancel();
    _retrievalTopKController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final storage = ref.read(storageServiceProvider);
    final locale = await storage.getLocale();
    final rag = await storage.getRagConfig();
    if (!mounted) {
      return;
    }
    setState(() {
      _localeDraft = locale;
      _retrievalTopKDraft = rag.retrievalTopK.toString();
      _retrievalModeDraft = rag.retrievalMode;
      _retrievalTopKController.text = _retrievalTopKDraft;
      _loading = false;
    });
  }

  void _updateLocale(String value) {
    setState(() {
      _localeDraft = value;
      _localeError = null;
    });
    _localeDebounce?.cancel();
    _localeDebounce = Timer(const Duration(milliseconds: 200), () async {
      try {
        await ref.read(localeControllerProvider.notifier).update(value);
      } catch (error) {
        if (!mounted) {
          return;
        }
        setState(() {
          _localeError = error.toString();
        });
      }
    });
  }

  void _updateRetrievalTopK(String value) {
    setState(() {
      _retrievalTopKDraft = value;
    });
    final parsed = _toPositiveInt(value);
    if (value.trim().isNotEmpty && parsed == null) {
      setState(() {
        _retrievalError = translate(ref.read(localeControllerProvider).locale, 'settings.error.invalidNumber',
            {'fields': translate(ref.read(localeControllerProvider).locale, 'settings.retrieval.topK')});
      });
      return;
    }
    setState(() {
      _retrievalError = null;
    });
    _retrievalDebounce?.cancel();
    _retrievalDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (parsed == null) {
        return;
      }
      await ref.read(storageServiceProvider).setRagConfig(retrievalTopK: parsed);
    });
  }

  void _updateRetrievalMode(String value) {
    setState(() {
      _retrievalModeDraft = value;
      _retrievalError = null;
    });
    _modeDebounce?.cancel();
    _modeDebounce = Timer(const Duration(milliseconds: 200), () async {
      await ref.read(storageServiceProvider).setRagConfig(retrievalMode: value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeControllerProvider).locale;
    final palette = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: Text(translate(locale, 'settings.title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(translate(locale, 'settings.autoSave'), style: TextStyle(color: palette.onSurface.withAlpha(140))),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(translate(locale, 'language.title')),
                  const SizedBox(height: 6),
                  Text(translate(locale, 'language.helper')),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: supportedLocales.map((item) {
                      final selected = _localeDraft == item;
                      return ChoiceChip(
                        label: Text(translate(locale, item == 'zh-CN' ? 'language.zh' : 'language.en')),
                        selected: selected,
                        onSelected: (_) => _updateLocale(item),
                      );
                    }).toList(),
                  ),
                  if (_localeError != null) ...[
                    const SizedBox(height: 8),
                    Text(_localeError!, style: TextStyle(color: palette.error)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: Text(translate(locale, 'settings.models.title')),
              subtitle: Text(translate(locale, 'settings.models.helper')),
              trailing: Icon(Icons.chevron_right, color: palette.primary),
              onTap: () => context.go('/settings/models'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(translate(locale, 'settings.retrieval.title')),
                  const SizedBox(height: 6),
                  Text(translate(locale, 'settings.retrieval.helper')),
                  const SizedBox(height: 12),
                  Text(translate(locale, 'settings.retrieval.topK')),
                  const SizedBox(height: 6),
                  TextField(
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '12'),
                    onChanged: _updateRetrievalTopK,
                    controller: _retrievalTopKController,
                  ),
                  if (_retrievalError != null) ...[
                    const SizedBox(height: 8),
                    Text(_retrievalError!, style: TextStyle(color: palette.error)),
                  ],
                  const SizedBox(height: 12),
                  Text(translate(locale, 'settings.retrieval.mode')),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      _ModeChip(
                        label: translate(locale, 'settings.retrieval.mode.hybrid'),
                        selected: _retrievalModeDraft == 'hybrid',
                        onTap: () => _updateRetrievalMode('hybrid'),
                      ),
                      _ModeChip(
                        label: translate(locale, 'settings.retrieval.mode.chunk'),
                        selected: _retrievalModeDraft == 'chunk',
                        onTap: () => _updateRetrievalMode('chunk'),
                      ),
                      _ModeChip(
                        label: translate(locale, 'settings.retrieval.mode.document'),
                        selected: _retrievalModeDraft == 'document',
                        onTap: () => _updateRetrievalMode('document'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int? _toPositiveInt(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}
