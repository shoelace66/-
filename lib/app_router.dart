import 'package:flutter/material.dart';

import 'core/presentation/pages/app_settings_page.dart';
import 'core/presentation/pages/assistant_config_page.dart';
import 'core/presentation/pages/provider_settings_page.dart';
import 'features/chat/domain/providers/chat_provider.dart';
import 'features/chat/presentation/pages/backup_restore_page.dart';
import 'features/chat/presentation/pages/chat_page.dart';
import 'features/chat/presentation/pages/conversation_timeline_page.dart';
import 'features/chat/presentation/pages/conversation_search_page.dart';
import 'features/chat/presentation/pages/memory_archive_page.dart';
import 'features/worldbook/presentation/pages/world_book_page.dart';
import 'features/media/presentation/pages/image_gallery_page.dart';

abstract final class AppRoutes {
  static const chat = '/';
  static const providerSettings = '/settings/providers';
  static const appSettings = '/settings/app';
  static const assistantSettings = '/settings/assistant';
  static const memoryArchive = '/conversation/memory';
  static const timeline = '/conversation/timeline';
  static const search = '/conversation/search';
  static const backup = '/data/backup';
  static const worldBook = '/worldbook';
  static const imageGallery = '/media/gallery';
}

class AppRouter {
  const AppRouter(this.provider);

  final ChatProvider provider;

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final page = switch (settings.name) {
      AppRoutes.chat => ChatPage(provider: provider),
      AppRoutes.providerSettings =>
        ProviderSettingsPage(initial: provider.providerSettings),
      AppRoutes.appSettings => AppSettingsPage(
          initial: provider.appSettings,
          onSave: provider.saveAppSettings,
        ),
      AppRoutes.assistantSettings => AssistantConfigPage(provider: provider),
      AppRoutes.memoryArchive => MemoryArchivePage(provider: provider),
      AppRoutes.timeline => ConversationTimelinePage(provider: provider),
      AppRoutes.search => ConversationSearchPage(provider: provider),
      AppRoutes.backup => BackupRestorePage(provider: provider),
      AppRoutes.worldBook => WorldBookPage(provider: provider),
      AppRoutes.imageGallery => ImageGalleryPage(provider: provider),
      _ => _UnknownRoutePage(routeName: settings.name),
    };
    return MaterialPageRoute<dynamic>(
      settings: settings,
      builder: (_) => page,
    );
  }
}

class _UnknownRoutePage extends StatelessWidget {
  const _UnknownRoutePage({required this.routeName});

  final String? routeName;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('页面不存在')),
        body: Center(child: Text('无法打开路由：${routeName ?? "(空)"}')),
      );
}
