import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/update_controller.dart';

/// Compact "update available" banner shown at the very top of the app.
/// Desktop: offers auto-download with progress, then reveal-in-folder.
/// Mobile: keeps the View link (no auto-install without store signing).
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateControllerProvider);
    final info = state.available;
    if (info == null || state.dismissed) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final notifier = ref.read(updateControllerProvider.notifier);

    final Widget leading;
    switch (state.downloadPhase) {
      case UpdateDownloadPhase.downloading:
        leading = SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: state.downloadProgress > 0 ? state.downloadProgress : null,
            color: scheme.primary,
          ),
        );
      case UpdateDownloadPhase.downloaded:
        leading = Icon(Icons.check_circle, size: 18, color: scheme.primary);
      case UpdateDownloadPhase.extracting:
      case UpdateDownloadPhase.ready:
      case UpdateDownloadPhase.failed:
        leading = Icon(Icons.error_outline, size: 18, color: scheme.error);
      case UpdateDownloadPhase.idle:
        leading = Icon(Icons.system_update, size: 18, color: scheme.primary);
    }

    final Widget action;
    switch (state.downloadPhase) {
      case UpdateDownloadPhase.idle:
        action = TextButton(
          onPressed: () async {
            await notifier.download();
          },
          child: const Text('Download'),
        );
      case UpdateDownloadPhase.downloading:
        action = Text(
          '${(state.downloadProgress * 100).toStringAsFixed(0)}%',
          style: Theme.of(context).textTheme.bodySmall,
        );
      case UpdateDownloadPhase.downloaded:
        action = TextButton(
          onPressed: () async {
            await notifier.revealDownload();
          },
          child: const Text('Show file'),
        );
      case UpdateDownloadPhase.extracting:
      case UpdateDownloadPhase.ready:
      case UpdateDownloadPhase.failed:
        action = TextButton(
          onPressed: () async {
            await notifier.download();
          },
          child: const Text('Retry'),
        );
    }

    return Material(
      color: scheme.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.downloadPhase == UpdateDownloadPhase.downloaded
                      ? 'v${info.version} downloaded'
                      : 'Update available: v${info.version}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              action,
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse(info.url),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('View'),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    ref.read(updateControllerProvider.notifier).dismiss(),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
