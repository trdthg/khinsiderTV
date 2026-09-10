import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/update_controller.dart';

/// Compact "update available" banner shown at the very top of the app.
/// Dismissible; the version link opens the GitHub release page.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateControllerProvider);
    final info = state.available;
    if (info == null || state.dismissed) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.system_update, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Update available: v${info.version}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
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
