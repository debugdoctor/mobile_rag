import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/storage_service.dart';

class LocaleState {
  const LocaleState({required this.locale, required this.isLoading});

  final String locale;
  final bool isLoading;

  LocaleState copyWith({String? locale, bool? isLoading}) {
    return LocaleState(
      locale: locale ?? this.locale,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class LocaleController extends StateNotifier<LocaleState> {
  LocaleController(this._storage)
      : super(const LocaleState(locale: 'en', isLoading: true)) {
    _load();
  }

  final StorageService _storage;

  Future<void> _load() async {
    final locale = await _storage.getLocale();
    state = state.copyWith(locale: locale, isLoading: false);
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    await _load();
  }

  Future<void> update(String next) async {
    await _storage.setLocale(next);
    await _load();
  }
}
