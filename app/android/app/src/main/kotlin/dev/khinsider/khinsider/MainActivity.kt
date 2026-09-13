package dev.khinsider.khinsider

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    /**
     * The media notification action icons.
     *
     * audio_service resolves a control's icon by name at runtime
     * (`Resources.getIdentifier`), which looks unused to the resource
     * optimizer - that is how the plugin's own drawables vanished from release
     * APKs, leaving every notification action with a null icon (SystemUI then
     * drops the action entirely, so the media card showed no buttons at all).
     * Referencing the array here keeps the icons reachable.
     */
    @Suppress("unused")
    private val mediaActionIcons = R.array.media_action_icons

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.khinsider/update")
            .setMethodCallHandler { call, result ->
                if (call.method == "installApk") {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("no_path", "APK path is missing", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            File(path),
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("install_failed", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }

        // Where the download cache may live: Android 11+ only lets an app write
        // into the public Music folder with "all files access"
        // (MANAGE_EXTERNAL_STORAGE), which the user grants on a system settings
        // screen instead of in a runtime permission dialog.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.khinsider/storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canWritePublicMusic" -> result.success(canWritePublicMusic())
                    "publicMusicPath" -> result.success(publicMusicPath())
                    "requestAllFilesAccess" -> {
                        requestAllFilesAccess()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // How the UI should behave on this device. TV layouts need their own
        // on-screen keyboard (see [isTelevision]).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.khinsider/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTelevision" -> result.success(isTelevision())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Whether this device is a TV (Android TV / Google TV / Fire TV).
     *
     * TV layouts type with the app's own on-screen keyboard: the system IME
     * they would otherwise show cannot be reached with a remote, because no
     * Flutter text field can hand the D-pad over to it (the framework consumes
     * arrow keys for focus traversal and caret movement first, so the key never
     * reaches the window manager).
     */
    private fun isTelevision(): Boolean =
        packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_TELEVISION)

    private fun canWritePublicMusic(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return Environment.isExternalStorageManager()
        }
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
        ) == PackageManager.PERMISSION_GRANTED
    }

    @Suppress("DEPRECATION")
    private fun publicMusicPath(): String? =
        Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC)?.absolutePath

    private fun requestAllFilesAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val appIntent = Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:$packageName"),
            )
            try {
                startActivity(appIntent)
            } catch (e: Exception) {
                // Some ROMs only expose the global list; a few have neither, in
                // which case the user has to go through system settings.
                try {
                    startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                } catch (ignored: Exception) {
                    // Nothing else we can do.
                }
            }
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                WRITE_EXTERNAL_STORAGE_REQUEST,
            )
        }
    }

    private companion object {
        const val WRITE_EXTERNAL_STORAGE_REQUEST = 4711
    }
}
