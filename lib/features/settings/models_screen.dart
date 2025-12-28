import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_providers.dart';
import '../../core/i18n.dart';

class ModelsScreen extends ConsumerWidget {
  const ModelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeControllerProvider).locale;
    final palette = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(translate(locale, 'settings.models.title')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            translate(locale, 'settings.models.subtitle'),
            style: TextStyle(color: palette.onSurface.withAlpha(170)),
          ),
          const SizedBox(height: 16),
          _CardLink(
            title: translate(locale, 'settings.models.chat'),
            subtitle: translate(locale, 'settings.models.chatDesc'),
            onTap: () => context.go('/settings/chat-models'),
          ),
          const SizedBox(height: 12),
          _CardLink(
            title: translate(locale, 'settings.models.embedding'),
            subtitle: translate(locale, 'settings.models.embeddingDesc'),
            onTap: () => context.go('/settings/embedding-models'),
          ),
        ],
      ),
    );
  }
}

class _CardLink extends StatelessWidget {
  const _CardLink({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.chevron_right, color: palette.primary),
        onTap: onTap,
      ),
    );
  }
}
