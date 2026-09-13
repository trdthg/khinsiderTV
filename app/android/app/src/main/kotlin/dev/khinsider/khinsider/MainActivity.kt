package dev.khinsider.khinsider

import android.Manifest
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.view.WindowManager
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
                    "exportToMusic" -> {
                        val relativePath = call.argument<String>("relativePath")
                        val displayName = call.argument<String>("displayName")
                        val sourcePath = call.argument<String>("sourcePath")
                        if (relativePath == null || displayName == null || sourcePath == null) {
                            result.error(
                                "bad_args",
                                "relativePath, displayName and sourcePath are required",
                                null,
                            )
                        } else {
                            result.success(
                                exportToMusic(
                                    relativePath = relativePath,
                                    displayName = displayName,
                                    sourcePath = sourcePath,
                                    mimeType = call.argument<String>("mimeType"),
                                    title = call.argument<String>("title"),
                                    artist = call.argument<String>("artist"),
                                    album = call.argument<String>("album"),
                                ),
                            )
                        }
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
                    "setKeepScreenOn" -> {
                        setKeepScreenOn(call.arguments as? Boolean ?: false)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Holds the screen on while audio plays (`FLAG_KEEP_SCREEN_ON`).
     *
     * A TV that lets its screen time out goes into ambient mode and then
     * standby, and standby stops playback: on a Chromecast the music dies on
     * its own after a while, which is what this prevents. The flag is tied to
     * the window, so it stops applying by itself once the app is not visible -
     * a paused player therefore still lets the device sleep.
     *
     * MethodChannel handlers already run on the main thread, so no hopping.
     */
    private fun setKeepScreenOn(on: Boolean) {
        if (on)
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
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

    /**
     * Copies one cached file into the public `Music/` folder through MediaStore.
     *
     * This is the permission-free route: since Android 10 an app may contribute
     * its own media without any permission, while writing there as a plain file
     * needs the "all files access" toggle. Returns `"exported"`, `"exists"`
     * (already contributed, so nothing was copied), `"unsupported"` (no
     * MediaStore route on this platform) or `"failed"`.
     *
     * [relativePath] is relative to the shared storage root and must end up
     * under a public media directory, e.g. `Music/KHInsider/Album Name`.
     */
    private fun exportToMusic(
        relativePath: String,
        displayName: String,
        sourcePath: String,
        mimeType: String?,
        title: String?,
        artist: String?,
        album: String?,
    ): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "unsupported"
        val source = File(sourcePath)
        if (!source.isFile) return "failed"

        val resolver = contentResolver
        val collection =
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        // MediaStore stores the path with a trailing separator.
        val path = relativePath.trimEnd('/') + "/"
        if (musicEntryExists(resolver, collection, path, displayName)) return "exists"

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.RELATIVE_PATH, path)
            // Hide the half-written file from other apps until it is complete.
            put(MediaStore.MediaColumns.IS_PENDING, 1)
            if (mimeType != null) put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            if (title != null) put(MediaStore.Audio.Media.TITLE, title)
            if (artist != null) put(MediaStore.Audio.Media.ARTIST, artist)
            if (album != null) put(MediaStore.Audio.Media.ALBUM, album)
            put(MediaStore.Audio.Media.IS_MUSIC, 1)
        }
        val uri = try {
            resolver.insert(collection, values)
        } catch (e: Exception) {
            null
        } ?: return "failed"

        return try {
            val out = resolver.openOutputStream(uri)
                ?: throw IllegalStateException("MediaStore returned no output stream")
            out.use { target -> source.inputStream().use { it.copyTo(target) } }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            "exported"
        } catch (e: Exception) {
            try {
                resolver.delete(uri, null, null)
            } catch (ignored: Exception) {
                // Leaving an empty pending row behind is harmless.
            }
            "failed"
        }
    }

    /**
     * Whether [displayName] is already in [relativePath].
     *
     * Matched on the display name and then compared by path (ignoring the
     * trailing separator MediaStore may or may not include), because a path
     * equality selection is unreliable across Android versions.
     */
    private fun musicEntryExists(
        resolver: ContentResolver,
        collection: Uri,
        relativePath: String,
        displayName: String,
    ): Boolean = try {
        resolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns.RELATIVE_PATH),
            "${MediaStore.MediaColumns.DISPLAY_NAME}=?",
            arrayOf(displayName),
            null,
        )?.use { cursor ->
            val column = cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
            val wanted = relativePath.trimEnd('/')
            var found = false
            while (cursor.moveToNext()) {
                if (column < 0) break
                if (cursor.getString(column)?.trimEnd('/') == wanted) {
                    found = true
                    break
                }
            }
            found
        } ?: false
    } catch (e: Exception) {
        false
    }

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
