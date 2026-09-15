import 'package:flutter/widgets.dart';

import '../state/locale_controller.dart';
import 'generated/app_localizations.dart';

/// The strings for [locale], for code that has no `BuildContext` (services and
/// controllers). Pass what `localeControllerProvider` currently holds; `null`
/// means English, which is the app's default.
AppLocalizations stringsFor(Locale? locale) =>
    lookupAppLocalizations(locale ?? defaultLanguage);

/// The locale the UI is currently showing.
///
/// Only for code that lives outside the widget tree and was built before it —
/// in practice the media session, which `main` creates before the first frame
/// and which puts the notification's action labels together. Everything else
/// takes `stringsFor` or a getter, so a language change is picked up at once.
Locale? currentUiLocale;

/// Shorthand for widgets: `l10n(context).settingsTitle`.
AppLocalizations l10n(BuildContext context) => AppLocalizations.of(context);
