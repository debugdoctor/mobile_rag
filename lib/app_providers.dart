import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database/app_database.dart';
import 'services/api_service.dart';
import 'services/db_service.dart';
import 'services/rag_service.dart';
import 'services/storage_service.dart';

import 'core/locale_controller.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final dbServiceProvider = Provider<DbService>((ref) {
  return DbService(ref.watch(databaseProvider));
});

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService(ref.watch(dbServiceProvider));
});

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(ref.watch(storageServiceProvider));
});

final ragServiceProvider = Provider<RagService>((ref) {
  return RagService(
    db: ref.watch(dbServiceProvider),
    storage: ref.watch(storageServiceProvider),
    api: ref.watch(apiServiceProvider),
  );
});

final localeControllerProvider = StateNotifierProvider<LocaleController, LocaleState>((ref) {
  return LocaleController(ref.watch(storageServiceProvider));
});
