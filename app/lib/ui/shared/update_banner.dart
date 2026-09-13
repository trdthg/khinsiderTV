import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/dpad_nav.dart';
import '../../core/widgets/dpad_tile.dart';
import '../../state/update_controller.dart';

/// Compact "update available" banner shown at the very top of the app.
/// Desktop: offers auto-download with progress, then reveal-in-folder.
/// Mobile: keeps the View link (no auto-install without store signing).
///
/// Its buttons are [DpadTile]s with their own focus nodes: a plain `TextButton`
/// is focusable, but on a TV/ChromeOS there is nothing to move the focus onto
/// it (arrow traversal has to walk in from another screen's widgets) and its
/// focus tint is invisible against the banner colour, so the banner looked
/// impossible to select. Here the ring is the app's usual one, Left/Right walk
/// the banner's own buttons explicitly (see [DpadNav]), and Select/Enter
/// activates whichever one is ringed.
class UpdateBanner extends ConsumerStatefulWidget {
  const UpdateBanner({super.key});

  @override
  ConsumerState<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<UpdateBanner> {
  final _actionFocus = FocusNode(debugLabel: 'update-action');
  final _viewFocus = FocusNode(debugLabel: 'update-view');
  final _closeFocus = FocusNode(debugLabel: 'update-close');

  @override
  void dispose() {
    _actionFocus.dispose();
    _viewFocus.dispose();
    _closeFocus.dispose();
    super.dispose();
  }

  /// A Material button wrapped in the app's focus ring. The inner button keeps
  /// its look but is kept out of the focus tree, so `DpadTile` owns the focus
  /// and Enter/Select land on it.
  Widget _button({
    required FocusNode focusNode,
    required Widget child,
    required VoidCallback onPressed,
    FocusNode? left,
    FocusNode? right,
  }) {
    return DpadNav(
      left: left,
      right: right,
      child: DpadTile(
        focusNode: focusNode,
        borderRadius: 18,
        onSelect: onPressed,
        child: ExcludeFocus(
          child: IgnorePointer(
            child: TextButton(onPressed: onPressed, child: child),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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

    // Every phase keeps the same three focus targets, so the ring does not jump
    // around while a download runs.
    final Widget action;
    switch (state.downloadPhase) {
      case UpdateDownloadPhase.idle:
        action = _button(
          focusNode: _actionFocus,
          right: _viewFocus,
          onPressed: () => notifier.download(),
          child: const Text('Download'),
        );
      case UpdateDownloadPhase.downloading:
        action = Text(
          '${(state.downloadProgress * 100).toStringAsFixed(0)}%',
          style: Theme.of(context).textTheme.bodySmall,
        );
      case UpdateDownloadPhase.downloaded:
        action = _button(
          focusNode: _actionFocus,
          right: _viewFocus,
          onPressed: () => notifier.revealDownload(),
          child: const Text('Show file'),
        );
      case UpdateDownloadPhase.extracting:
      case UpdateDownloadPhase.ready:
      case UpdateDownloadPhase.failed:
        action = _button(
          focusNode: _actionFocus,
          right: _viewFocus,
          onPressed: () => notifier.retryDownload(),
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
                  state.downloadPhase == UpdateDownloadPhase.failed
                      ? (state.errorMessage ?? 'Update failed')
                      : state.downloadPhase == UpdateDownloadPhase.ready
                      ? 'v${info.version} ready to install'
                      : 'Update available: v${info.version}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              action,
              _button(
                focusNode: _viewFocus,
                left: _actionFocus,
                right: _closeFocus,
                onPressed: () => launchUrl(
                  Uri.parse(info.url),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('View'),
              ),
              DpadNav(
                left: _viewFocus,
                child: DpadIconButton(
                  focusNode: _closeFocus,
                  tooltip: 'Dismiss this update notice',
                  iconSize: 18,
                  icon: Icons.close,
                  onPressed: () => notifier.dismiss(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
