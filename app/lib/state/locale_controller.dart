import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/preferences_store.dart';

/// The interface language.
///
/// English is what the app opens with, no matter what the system is set to:
/// that is the deliberate default, and the 简体中文 entry in Settings is how it
/// is changed. The choice is written straight to the key-value store, so it is
/// already there on the next launch.
///
/// The value is `null` only for the moment before the store has been read (and
/// if the read fails); [KhinsiderApp] treats that as English, which keeps the
/// first frame from flickering through the system locale.
const _kLanguage = 'ui-language';

const List<Locale> supportedLanguages = [Locale('en'), Locale('zh')];

/// The default, and the fallback for anything unrecognised.
const Locale defaultLanguage = Locale('en');

Locale? languageFromCode(Object? code) {
  if (code is! String) return null;
  for (final locale in supportedLanguages) {
    if (locale.languageCode == code) return locale;
  }
  return null;
}

class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() {
    unawaited(_restore());
    return null;
  }

  Future<void> _restore() async {
    try {
      final store = await ref.read(jsonKvStoreProvider.future);
      final saved = languageFromCode(store.read<String>(_kLanguage));
      if (saved != null && ref.mounted) state = saved;
    } catch (_) {
      // No store (a test, or a broken documents directory): the default is
      // already in place, so there is nothing to do.
    }
  }

  Future<void> set(Locale locale) async {
    // Applied first: switching language must not wait on a disk write.
    state = locale;
    try {
      final store = await ref.read(jsonKvStoreProvider.future);
      store.write(_kLanguage, locale.languageCode);
    } catch (_) {}
  }
}

final localeControllerProvider = NotifierProvider<LocaleController, Locale?>(
  LocaleController.new,
);
