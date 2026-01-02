import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_providers.dart';
import 'core/app_theme.dart';
import 'core/i18n.dart';
import 'features/chat/chat_screen.dart';
import 'features/knowledge/knowledge_screen.dart';
import 'features/knowledge/knowledge_detail_screen.dart';
import 'features/knowledge/knowledge_settings_screen.dart';
import 'features/knowledge/document_chunks_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/models_screen.dart';
import 'features/settings/chat_models_screen.dart';
import 'features/settings/embedding_models_screen.dart';
import 'features/settings/prompt_templates_screen.dart';

final _router = GoRouter(
  initialLocation: '/chat',
  routes: [
    GoRoute(
      path: '/',
      redirect: (_, _) => '/chat',
    ),
    ShellRoute(
      builder: (context, state, child) => _MainShell(child: child),
      routes: [
        GoRoute(
          path: '/chat',
          builder: (context, state) => const ChatScreen(),
        ),
        GoRoute(
          path: '/knowledge',
          builder: (context, state) => const KnowledgeScreen(),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) => KnowledgeDetailScreen(
                knowledgeBaseId: state.pathParameters['id']!,
              ),
            ),
            GoRoute(
              path: ':id/settings',
              builder: (context, state) => KnowledgeSettingsScreen(
                knowledgeBaseId: state.pathParameters['id']!,
              ),
            ),
            GoRoute(
              path: ':id/chunks/:docId',
              builder: (context, state) => DocumentChunksScreen(
                knowledgeBaseId: state.pathParameters['id']!,
                documentId: state.pathParameters['docId']!,
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
          routes: [
            GoRoute(
              path: 'models',
              builder: (context, state) => const ModelsScreen(),
              routes: [
                GoRoute(
                  path: 'chat-models',
                  builder: (context, state) => const ChatModelsScreen(),
                ),
                GoRoute(
                  path: 'embedding-models',
                  builder: (context, state) => const EmbeddingModelsScreen(),
                ),
              ],
            ),
            GoRoute(
              path: 'prompts',
              builder: (context, state) => const PromptTemplatesScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);

class App extends ConsumerWidget {
  const App({super.key});

  Locale _parseLocale(String localeString) {
    final parts = localeString.split('-');
    if (parts.length == 2) {
      return Locale(parts[0], parts[1]);
    }
    return Locale(localeString);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeControllerProvider).locale;

    return MaterialApp.router(
      title: translate(locale, 'app.title'),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: _router,
      locale: _parseLocale(locale),
      supportedLocales: supportedLocales.map((l) => _parseLocale(l)).toList(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

class _MainShell extends ConsumerWidget {
  const _MainShell({required this.child});

  final Widget child;

  int _locationToIndex(String location) {
    if (location.startsWith('/knowledge')) {
      return 1;
    }
    if (location.startsWith('/settings')) {
      return 2;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _locationToIndex(location);
    final locale = ref.watch(localeControllerProvider).locale;

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) {
          switch (index) {
            case 1:
              context.go('/knowledge');
              break;
            case 2:
              context.go('/settings');
              break;
            case 0:
            default:
              context.go('/chat');
          }
        },
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: translate(locale, 'nav.chat'),
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_books_outlined),
            label: translate(locale, 'nav.knowledge'),
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: translate(locale, 'nav.settings'),
          ),
        ],
      ),
    );
  }
}
