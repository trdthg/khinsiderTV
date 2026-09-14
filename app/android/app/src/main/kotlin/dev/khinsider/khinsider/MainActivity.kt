package dev.khinsider.khinsider

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
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

    /** Where the system sends the result of a package-installer session. */
    private var updateChannel: MethodChannel? = null
    private var installReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The TV search field: a real EditText, because Flutter's own text input
        // never hands the D-pad to the platform keyboard on Google TV (see
        // TvTextFieldView).
        flutterEngine.platformViewsController.registry.registerViewFactory(
            TvTextFieldView.CHANNEL_NAME,
            TvTextFieldFactory(flutterEngine.dartExecutor.binaryMessenger),
        )
        val update = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.khinsider/update",
        )
        updateChannel = update
        registerInstallReceiver()
        update.setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("no_path", "APK path is missing", null)
                        return@setMethodCallHandler
                    }
                    val file = File(path)
                    if (!file.exists()) {
                        result.error("missing_file", "APK is gone: $path", null)
                        return@setMethodCallHandler
                    }
                    // Preferred: hand the bytes to the system installer through a
                    // session. It needs no content:// URI, so nothing can fail
                    // because the installer could not read our file, and the
                    // result comes back as a status code we can show the user.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        try {
                            startInstallSession(file)
                            result.success("session")
                            return@setMethodCallHandler
                        } catch (e: Exception) {
                            // Fall through to the intent path below.
                        }
                    }
                    try {
                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            file,
                        )
                        val view = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        // Most launchers/TVs handle ACTION_VIEW for an APK, but a
                        // plain Android TV image may only have the package
                        // installer, which also answers ACTION_INSTALL_PACKAGE.
                        val intent =
                            if (view.resolveActivity(packageManager) != null) {
                                view
                            } else {
                                Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                                    data = uri
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
                                }
                            }
                        if (intent.resolveActivity(packageManager) == null) {
                            result.error(
                                "no_installer",
                                "No activity can install an APK on this device",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        startActivity(intent)
                        result.success("intent")
                    } catch (e: Exception) {
                        result.error("install_failed", e.message, null)
                    }
                }
                // Android 8+ additionally requires the user to allow "install
                // unknown apps" for this app; without it the installer opens
                // and instantly does nothing, which is impossible to explain
                // to the user from the Dart side.
                "canInstallPackages" ->
                    result.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            packageManager.canRequestPackageInstalls()
                        } else {
                            true
                        },
                    )
                "openInstallSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName"),
                                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                            )
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("settings_failed", e.message, null)
                    }
                }
                // The ABI this installation actually runs, so an update can fetch
                // the 17MB per-ABI APK instead of the 37MB universal one.
                "androidAbi" -> result.success(currentAbi())
                else -> result.notImplemented()
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

        /** Where the system sends the result of a package-installer session. */
        const val ACTION_INSTALL_RESULT = "dev.khinsider.INSTALL_RESULT"
    }

    /**
     * The ABI of the *installed* APK, read from where its native libraries were
     * extracted. On a 32-bit-only install of a fat APK this is `.../lib/arm`,
     * which is exactly what decides whether the armv7 or the arm64 update is
     * the right download.
     */
    private fun currentAbi(): String {
        val dir = applicationInfo?.nativeLibraryDir ?: return "universal"
        return when {
            dir.endsWith("arm64") -> "arm64"
            dir.contains("armeabi") || dir.endsWith("arm") -> "armv7"
            dir.contains("x86_64") -> "x86_64"
            dir.contains("x86") -> "x86"
            else -> "universal"
        }
    }

    /** Streams [file] into a package-installer session and commits it. */
    private fun startInstallSession(file: File) {
        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL,
        )
        val length = file.length()
        params.setSize(length)
        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            session.openWrite("base.apk", 0, length).use { output ->
                file.inputStream().use { input -> input.copyTo(output) }
                session.fsync(output)
            }
            val callback = Intent(ACTION_INSTALL_RESULT).setPackage(packageName)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        PendingIntent.FLAG_MUTABLE
                    } else {
                        0
                    }
                )
            val pending = PendingIntent.getBroadcast(this, sessionId, callback, flags)
            session.commit(pending.intentSender)
        }
    }

    /**
     * Forwards the installer's verdict to Dart. The system tells us *why* an
     * install failed (bad signature, no space, incompatible ABI, ...), which is
     * the one thing the user could never see before.
     */
    private fun registerInstallReceiver() {
        if (installReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != ACTION_INSTALL_RESULT) return
                val status = intent.getIntExtra(
                    PackageInstaller.EXTRA_STATUS,
                    PackageInstaller.STATUS_FAILURE,
                )
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                // The session API asks the caller to show the confirmation UI
                // itself; without this the install silently waits forever.
                if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                    @Suppress("DEPRECATION")
                    val confirm = intent.getParcelableExtra(Intent.EXTRA_INTENT) as? Intent
                    if (confirm != null) {
                        confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        runCatching { (context ?: this@MainActivity).startActivity(confirm) }
                    }
                }
                updateChannel?.invokeMethod(
                    "installResult",
                    mapOf("status" to status, "message" to message),
                )
            }
        }
        val filter = IntentFilter(ACTION_INSTALL_RESULT)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
        installReceiver = receiver
    }

    override fun onDestroy() {
        installReceiver?.let { receiver -> runCatching { unregisterReceiver(receiver) } }
        installReceiver = null
        super.onDestroy()
    }
}
