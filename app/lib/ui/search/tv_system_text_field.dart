import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The TV search field: a real Android `EditText`, embedded as a platform view.
///
/// A Flutter `TextField` cannot be typed into with a TV remote on Google TV /
/// Chromecast. The platform keyboard opens, but the arrow keys keep moving the
/// caret inside the field behind it — the IME never gets them — so nothing can
/// be entered (flutter/flutter#177360, #154924, #125541). The engine's
/// `InputConnectionAdaptor` is what the IME talks to there, and it consumes the
/// D-pad; a native `EditText` does not, which is why the platform keyboard is
/// fully navigable in every non-Flutter TV app, and why this widget exists.
///
/// So the TV field is a native view (see `TvTextFieldView.kt`): Flutter draws
/// the box, hint and layout, and the `EditText` inside it owns the IME. Text and
/// events cross a per-view `MethodChannel`; the D-pad directions that leave the
/// field (Down to the results, Left to the keyboard-mode button, Up towards the
/// update banner) come back as callbacks, because a platform view holds the
/// focus while the IME is closed.
///
/// Only used on TVs; phones and desktops keep the ordinary [TextField].
class TvSystemTextField extends StatefulWidget {
  const TvSystemTextField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onSubmitted,
    required this.onMoveDown,
    required this.onMoveUp,
    this.autoFocus = false,
    this.height = 48,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onSubmitted;

  /// The remote left the field. A platform view holds the focus itself, so the
  /// host screen has to move it.
  final VoidCallback onMoveDown;
  final VoidCallback onMoveUp;

  /// Take the focus as soon as the native view exists, *without* raising the
  /// keyboard. A platform view is not a Flutter focus target, so a field that
  /// never takes focus on its own cannot be reached with a remote at all.
  final bool autoFocus;

  final double height;

  @override
  State<TvSystemTextField> createState() => TvSystemTextFieldState();
}

class TvSystemTextFieldState extends State<TvSystemTextField> {
  /// View type registered by the Android host (see `MainActivity`).
  static const String _viewType = 'dev.khinsider/tvtextfield';

  MethodChannel? _channel;

  /// Text last known to be in the native field, so a change that came *from*
  /// the native side is not pushed straight back at it.
  String _nativeText = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _nativeText = widget.controller.text;
  }

  @override
  void didUpdateWidget(TvSystemTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _nativeText = widget.controller.text;
      _pushText();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _onControllerChanged() {
    if (widget.controller.text == _nativeText) return;
    _pushText();
  }

  /// Dart changed the text (a history chip, or clearing after a search).
  void _pushText() {
    final text = widget.controller.text;
    _nativeText = text;
    unawaited(
      _channel?.invokeMethod<void>('setText', text) ?? Future<void>.value(),
    );
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('$_viewType/$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onChanged':
          final text = call.arguments as String? ?? '';
          _nativeText = text;
          // Only the selection is written back: replacing the whole value
          // would move the native caret to the end on every keystroke.
          widget.controller.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
        case 'onSubmitted':
          widget.onSubmitted(call.arguments as String? ?? '');
        case 'onMoveDown':
          widget.onMoveDown();
        case 'onMoveUp':
          widget.onMoveUp();
      }
      return null;
    });
    _nativeText = widget.controller.text;
    _pushText();
    if (widget.autoFocus) requestFocus(showKeyboard: false);
  }

  /// Focuses the native field, and by default raises the platform keyboard.
  ///
  /// Pass `showKeyboard: false` for the focus the screen sets up by itself:
  /// on a TV that keyboard covers the whole screen, and the user has not asked
  /// to type anything yet.
  void requestFocus({bool showKeyboard = true}) {
    unawaited(
      _channel?.invokeMethod<void>('focus', showKeyboard) ??
          Future<void>.value(),
    );
  }

  /// Drops the keyboard and the focus (after a search: the results are next).
  void blur() {
    unawaited(_channel?.invokeMethod<void>('blur') ?? Future<void>.value());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: widget.height,
      child: AndroidView(
        viewType: _viewType,
        creationParams: <String, Object?>{
          'text': widget.controller.text,
          'hint': widget.hintText,
          'textColor': scheme.onSurface.toARGB32(),
          'hintColor': scheme.onSurfaceVariant.toARGB32(),
          'textSize': 16.0,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }
}
