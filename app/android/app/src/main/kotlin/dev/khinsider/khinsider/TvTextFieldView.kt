package dev.khinsider.khinsider

import android.content.Context
import android.graphics.Color
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.util.TypedValue
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * The TV search field, backed by a real Android `EditText`.
 *
 * Why a platform view instead of a Flutter `TextField`: on Google TV /
 * Chromecast the system keyboard (Gboard TV) opens for a Flutter text field but
 * never takes the D-pad - the arrow keys keep moving the caret behind the
 * keyboard, so nothing can be typed. That is a Flutter-side limitation of the
 * engine's `InputConnectionAdaptor` (flutter/flutter#177360, #154924, #125541);
 * the same Gboard TV *is* fully D-pad navigable when the focused editor is a
 * platform `EditText`, which is the workaround that upstream thread documents.
 * The app used to draw its own D-pad keyboard to work around this; with a real
 * `EditText` the platform's own keyboard is usable and that panel is gone.
 *
 * One trap, from that same thread: `inputType` must be set exactly once.
 * Re-assigning it calls `restartInput()`, and Gboard TV then forgets which key
 * was highlighted after every keystroke.
 */
class TvTextFieldFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = (args as? Map<String, Any?>) ?: emptyMap()
        return TvTextFieldView(context, messenger, viewId, params)
    }
}

class TvTextFieldView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    params: Map<String, Any?>,
) : PlatformView {
    private val editText = EditText(context)
    private val channel = MethodChannel(messenger, "$CHANNEL_NAME/$viewId")
    private val density = context.resources.displayMetrics.density

    /** True while Dart is setting the text, so the echo is not sent back. */
    private var applyingFromDart = false

    init {
        editText.apply {
            // Set ONCE - see the class comment.
            inputType = InputType.TYPE_CLASS_TEXT
            imeOptions = EditorInfo.IME_ACTION_SEARCH or EditorInfo.IME_FLAG_NO_FULLSCREEN
            setSingleLine(true)
            setBackgroundColor(Color.TRANSPARENT)
            setPadding(
                (12 * density).toInt(),
                0,
                (12 * density).toInt(),
                0,
            )
            setTextColor(params.color("textColor", Color.WHITE))
            setHintTextColor(params.color("hintColor", Color.GRAY))
            hint = params["hint"] as? String
            setTextSize(
                TypedValue.COMPLEX_UNIT_SP,
                (params["textSize"] as? Number)?.toFloat() ?: 16f,
            )
            isFocusable = true
            isFocusableInTouchMode = true
            setText(params["text"] as? String ?: "")
            setSelection(text.length)
        }

        editText.addTextChangedListener(
            object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) = Unit
                override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) = Unit
                override fun afterTextChanged(s: Editable?) {
                    if (applyingFromDart) return
                    channel.invokeMethod("onChanged", s?.toString() ?: "")
                }
            },
        )

        editText.setOnEditorActionListener { _, actionId, event ->
            // Separate val: `event != null &&` is what lets the smart cast see
            // a non-null KeyEvent on the next line.
            val pressedEnter =
                event != null &&
                    event.keyCode == KeyEvent.KEYCODE_ENTER &&
                    event.action == KeyEvent.ACTION_DOWN
            val submitted =
                actionId == EditorInfo.IME_ACTION_SEARCH ||
                    actionId == EditorInfo.IME_ACTION_DONE ||
                    pressedEnter
            if (submitted) {
                channel.invokeMethod("onSubmitted", editText.text.toString())
            }
            submitted
        }

        // The D-pad only reaches the EditText while the IME is closed (with it
        // open the arrow keys belong to Gboard), which is exactly when leaving
        // the field should work: Down to the results, Up towards the update
        // banner. Left/Right stay inside the text (they move the caret).
        editText.setOnKeyListener { _, keyCode, event ->
            if (event.action != KeyEvent.ACTION_DOWN) return@setOnKeyListener false
            when (keyCode) {
                KeyEvent.KEYCODE_DPAD_DOWN -> {
                    channel.invokeMethod("onMoveDown", null)
                    true
                }
                KeyEvent.KEYCODE_DPAD_UP -> {
                    channel.invokeMethod("onMoveUp", null)
                    true
                }
                KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> {
                    // "I want to type": the field is focused silently on
                    // purpose, so OK is what brings the platform keyboard up.
                    showIme()
                    false
                }
                else -> false
            }
        }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setText" -> {
                    val text = call.arguments as? String ?: ""
                    if (text != editText.text.toString()) {
                        applyingFromDart = true
                        editText.setText(text)
                        editText.setSelection(editText.text.length)
                        applyingFromDart = false
                    }
                    result.success(null)
                }
                "focus" -> {
                    // The host decides whether the keyboard comes with the
                    // focus: the initial focus must not raise it, or it covers
                    // the screen the moment the search box appears.
                    val showKeyboard = call.arguments as? Boolean ?: true
                    editText.requestFocus()
                    if (showKeyboard) showIme()
                    result.success(null)
                }
                "blur" -> {
                    hideIme()
                    editText.clearFocus()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // No focus and no keyboard here: a screen that wants the field focused
        // says so through "autoFocus" (focus only), and the keyboard comes up
        // when the user actually means to type - OK on the remote, or a tap.
    }

    private fun showIme() {
        val imm = editText.context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        imm?.showSoftInput(editText, InputMethodManager.SHOW_IMPLICIT)
    }

    private fun hideIme() {
        val imm = editText.context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        imm?.hideSoftInputFromWindow(editText.windowToken, 0)
    }

    override fun getView(): View = editText

    override fun dispose() {
        hideIme()
        channel.setMethodCallHandler(null)
    }

    companion object {
        const val CHANNEL_NAME = "dev.khinsider/tvtextfield"
    }
}

private fun Map<String, Any?>.color(key: String, fallback: Int): Int =
    (this[key] as? Number)?.toInt() ?: fallback
