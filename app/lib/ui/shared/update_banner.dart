import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform/device.dart';
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
///
/// On a TV the banner also *takes* the remote when it appears, and gives it
/// back on Down (or when it is dismissed). Wiring the buttons to each other was
/// not enough: the screens deliberately navigate by region (`skipTraversal`
/// containers, explicit `DpadNav`), so Flutter's geometric traversal has no
/// path from, say, the search field up into this row — the user could see the
/// update button but never reach it. The banner appears at most once per
/// version, so taking the focus once is cheap; [FocusNode] memory of where the
/// remote was makes backing out (Down) land exactly where the user left off.
class UpdateBanner extends ConsumerStatefulWidget {
  const UpdateBanner({super.key});

  @override
  ConsumerState<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<UpdateBanner> {
  final _actionFocus = FocusNode(debugLabel: 'update-action');
  final _viewFocus = FocusNode(debugLabel: 'update-view');
  final _closeFocus = FocusNode(debugLabel: 'update-close');

  /// Where the remote was before the banner took it, so Down (or dismissing
  /// the banner) puts it back instead of leaving the user with a dead remote.
  FocusNode? _returnFocus;

  /// Whether this banner has taken the remote already.
  bool _tookFocus = false;

  @override
  void dispose() {
    _actionFocus.dispose();
    _viewFocus.dispose();
    _closeFocus.dispose();
    super.dispose();
  }

  /// Takes the remote when the banner shows up on a TV, and hands it back when
  /// the banner goes away.
  ///
  /// Post-frame because focus cannot move while the tree is being built, and
  /// guarded by [_tookFocus] so a rebuild (a download ticking over, say) never
  /// yanks the focus back from wherever the user went.
  void _maybeTakeFocus({required bool visible}) {
    if (!ref.read(isTelevisionProvider)) return;
    if (visible && !_tookFocus) {
      _tookFocus = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final focused = FocusManager.instance.primaryFocus;
        // Someone (or something) already owns the banner: leave it alone.
        if (focused?.debugLabel?.startsWith('update-') ?? false) return;
        _returnFocus = focused;
        _actionFocus.requestFocus();
      });
    } else if (!visible && _tookFocus) {
      _tookFocus = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restoreFocus();
      });
    }
  }

  /// Hands the remote back to whatever had it before the banner. Returns false
  /// when there is nothing to hand it to, so the caller can fall through to the
  /// normal traversal instead.
  bool _restoreFocus() {
    final target = _returnFocus;
    _returnFocus = null;
    if (target != null && target.canRequestFocus && target.context != null) {
      target.requestFocus();
      return true;
    }
    if (!mounted) return false;
    // The widget that had it is gone: step down into the content instead.
    return FocusScope.of(context).focusInDirection(TraversalDirection.down);
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
    final visible = info != null && !state.dismissed;
    _maybeTakeFocus(visible: visible);
    if (!visible) return const SizedBox.shrink();

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
        // Still a focus target: the ring must not vanish the moment the
        // download starts, or a remote user is left with no way to reach View
        // or close (the node would be detached and focus would go nowhere).
        action = DpadNav(
          right: _viewFocus,
          child: DpadTile(
            focusNode: _actionFocus,
            borderRadius: 18,
            onSelect: () {},
            child: ExcludeFocus(
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '${(state.downloadProgress * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          ),
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

    return Focus(
      // A container, not a stop: without these two the geometric traversal
      // lands on this node instead of the buttons inside it, which is the bug
      // that made the banner unselectable in the first place.
      canRequestFocus: false,
      skipTraversal: true,
      // Down leaves the banner without having to find the close button.
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          if (_restoreFocus()) return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
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
                    onPressed: () {
                      notifier.dismiss();
                      _restoreFocus();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
