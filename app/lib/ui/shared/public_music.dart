import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/preferences_store.dart';
import '../../state/track_cache_controller.dart';

/// Explains why the cache can only move into the system `Music/` folder after
/// the user flips a switch on a *system settings* screen (Android 11+ calls
/// that "all files access"; it is not a runtime permission dialog) and sends
/// them there. Returns true when the user chose to go.
///
/// Shared by the cache-folder row on the album page and the first-launch
/// prompt so both say exactly the same thing.
Future<bool> offerPublicMusicFolder(BuildContext context, WidgetRef ref) async {
  final cache = ref.read(audioCacheManagerProvider);
  if (!cache.supportsPublicMusicFolder) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Save songs in the system Music folder?'),
      content: const Text(
        'Android only lets an app write into Music/ once you grant it "all '
        'files access" — the next screen has that switch for KHInsider.\n\n'
        'Downloads then land in Music/KHInsider, where your file manager, '
        'other players and your computer can see them. Tracks that are '
        'already downloaded stay in the app folder until you delete or move '
        'them.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Open settings'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  // Forget the resolved root BEFORE leaving for Settings: the next cache
  // access re-resolves it, so a grant takes effect without restarting the app.
  cache.forgetRoot();
  await cache.requestPublicMusicAccess();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Turn on "all files access", then come back: new downloads go to '
          'Music/KHInsider.',
        ),
      ),
    );
  }
  return true;
}

/// Android only, asked once: whether the download cache should live in the
/// system `Music/` folder instead of the app's private folder.
///
/// Renders nothing (and changes no layout) on other platforms, once the
/// question has been answered, and as soon as the cache already uses the
/// public folder. The "asked" flag is persisted immediately so a crash or a
/// force-quit cannot turn this into a prompt on every launch.
class PublicMusicPrompt extends ConsumerStatefulWidget {
  const PublicMusicPrompt({super.key, required this.navigatorKey});

  /// The app's navigator: this widget lives above it (inside
  /// `MaterialApp.builder`), so it cannot look one up with `Navigator.of`.
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  ConsumerState<PublicMusicPrompt> createState() => _PublicMusicPromptState();
}

class _PublicMusicPromptState extends ConsumerState<PublicMusicPrompt> {
  static const String _promptedKey = 'public_music_prompted';

  bool _asked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybePrompt());
    });
  }

  Future<void> _maybePrompt() async {
    if (_asked) return;
    _asked = true;

    final cache = ref.read(audioCacheManagerProvider);
    if (!cache.supportsPublicMusicFolder) return;

    final store = await ref.read(jsonKvStoreProvider.future);
    if (store.read<bool>(_promptedKey) ?? false) return;
    if (await cache.isUsingPublicMusicFolder) return;
    store.write(_promptedKey, true);

    if (!mounted) return;
    final context = widget.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await offerPublicMusicFolder(context, ref);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
