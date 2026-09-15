import 'package:flutter/material.dart';

import '../../core/widgets/dpad_tile.dart';
import '../../l10n/l10n.dart';

/// A titled group of [SettingsRow]s, drawn as one rounded card.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Divider(
            height: 1,
            thickness: 1,
            indent: 14,
            endIndent: 14,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        );
      }
      rows.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: rows),
          ),
        ],
      ),
    );
  }
}

/// One line in a [SettingsSection].
///
/// Every row is a [DpadTile], so a remote can land on all of them, including
/// the ones that only show a value. Whether a row *does* anything when it is
/// selected is a separate question: with no [onSelect] it is simply inert.
///
/// Keeping those two things apart is what makes the focus order stable. A row
/// used to change widget type — tile with an action, plain text without — every
/// time its action came and went (while a check was running, say), and the
/// focus ring moved to a neighbour each time the list changed shape.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.leading,
    this.trailing,
    this.onSelect,
    this.danger = false,
    this.focusNode,
    this.autofocus = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;

  /// Null leaves the row inert: it still takes focus, but selecting it does
  /// nothing. Only rows that could never be useful keep it that way.
  final VoidCallback? onSelect;

  /// Paints the title/icon in the error colour.
  final bool danger;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 14),
          ] else if (icon != null) ...[
            Icon(
              icon,
              size: 22,
              color: danger ? scheme.error : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: danger ? scheme.error : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (trailing != null) const SizedBox(width: 12),
          ?trailing,
        ],
      ),
    );
    return DpadTile(
      focusNode: focusNode,
      autofocus: autofocus,
      borderRadius: 14,
      onSelect: onSelect ?? _inert,
      child: content,
    );
  }
}

/// Back arrow + screen title, used instead of an [AppBar] so the header button
/// is the same [DpadTile] the rest of the app navigates with.
class SettingsHeader extends StatelessWidget {
  const SettingsHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = l10n(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
      child: Row(
        children: [
          DpadIconButton(
            icon: Icons.arrow_back,
            tooltip: l.actionBack,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
          ?trailing,
        ],
      ),
    );
  }
}

/// Selecting a row that has no action must not do anything — but the row still
/// has to be selectable, so [DpadTile] gets something to call.
void _inert() {}

/// `1.2 GB` / `345 MB` / `12 KB`.
String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}
