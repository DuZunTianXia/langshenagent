package dev.langshenagent.mobile

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.provider.Settings
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.Window
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.Executors

/// The app's native side: the method channels the Dart asks
/// (`langshenagent/app`, `langshenagent/update`, `langshenagent/haptics`, `langshenagent/shared`),
/// files other apps share in, and installing an update over itself.
class MainActivity : FlutterActivity() {
    private val sharedItems = ArrayList<Map<String, Any>>()
    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())


    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) takeShared(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        takeShared(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "langshenagent/app").setMethodCallHandler { call, result ->
            when (call.method) {
                "keepAlive" -> {
                    val title = call.argument<String>("title") ?: "LangshenAgent"
                    val text = call.argument<String>("text") ?: ""
                    val channel = call.argument<String>("channelName") ?: title
                    result.success(startKeepAlive(title, text, channel))
                }
                "letGo" -> {
                    stopService(Intent(this, KeepAliveService::class.java))
                    result.success(null)
                }
                "batteryExempt" -> {
                    // Doze-free networking: asks once to whitelist the
                    // app; true when already exempted (nothing opened).
                    val pm = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                    val ignored = pm.isIgnoringBatteryOptimizations(packageName)
                    if (!ignored) {
                        startActivity(
                            Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                    }
                    result.success(ignored)
                }
                "toBack" -> {
                    moveTaskToBack(true)
                    result.success(null)
                }
                "take" -> {
                    result.success(ArrayList(sharedItems))
                    sharedItems.clear()
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "langshenagent/shared").setMethodCallHandler { call, result ->
            if (call.method == "take") {
                result.success(ArrayList(sharedItems))
                sharedItems.clear()
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(messenger, "langshenagent/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstall" -> result.success(
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                        packageManager.canRequestPackageInstalls(),
                )
                "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "openInstallSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startActivity(
                            Intent(
                                android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                    }
                    result.success(null)
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("bad", "no path", null)
                    } else {
                        executor.execute { install(File(path), result) }
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "langshenagent/haptics").setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> {
                    haptic(call.argument<String>("kind") ?: "")
                    result.success(null)
                }
                "prepare" -> result.success(null)
                else -> result.notImplemented()
            }
        }

    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }

    private fun startKeepAlive(title: String, text: String, channel: String): Boolean =
        try {
            startForegroundService(
                Intent(this, KeepAliveService::class.java)
                    .putExtra("title", title)
                    .putExtra("text", text)
                    .putExtra("channelName", channel),
            )
            true
        } catch (_: Exception) {
            false
        }

    /// Files another app shared in (`SEND`, `SEND_MULTIPLE`, `VIEW`):
    /// copied to the cache (the grants do not last), queued for `take`.
    private fun takeShared(intent: Intent?) {
        val action = intent?.action ?: return
        val uris: List<Uri> = when (action) {
            Intent.ACTION_SEND -> listOfNotNull(
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                },
            )
            Intent.ACTION_SEND_MULTIPLE -> {
                val list = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                }
                list ?: emptyList()
            }
            Intent.ACTION_VIEW -> listOfNotNull(intent.data)
            else -> emptyList()
        }
        if (uris.isEmpty()) return
        executor.execute {
            for (uri in uris) {
                copyShared(uri)?.let { sharedItems.add(it) }
            }
        }
    }

    private fun copyShared(uri: Uri): Map<String, Any>? {
        val resolver = contentResolver
        val name = runCatching {
            resolver.query(uri, null, null, null, null)?.use { cursor ->
                val index = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (index >= 0 && cursor.moveToFirst()) cursor.getString(index) else null
            }
        }.getOrNull() ?: uri.lastPathSegment ?: "file"
        val mime = resolver.getType(uri) ?: "application/octet-stream"
        val dir = File(cacheDir, "shared").apply { mkdirs() }
        val safe = name.replace(Regex("[^\\w.\\-]"), "_")
        val file = File(dir, "${System.currentTimeMillis()}-$safe")
        return try {
            resolver.openInputStream(uri)?.use { input ->
                FileOutputStream(file).use { output -> input.copyTo(output) }
            } ?: return null
            mapOf("path" to file.absolutePath, "name" to name, "mime" to mime)
        } catch (_: Exception) {
            null
        }
    }

    /// Installs the package at [file] over this app (the update flow):
    /// the system's installer opened on it through a FileProvider — the
    /// way most updaters do it, no install-status broadcast needed.
    private fun install(file: File, result: MethodChannel.Result) {
        try {
            val uri = androidx.core.content.FileProvider.getUriForFile(
                this, "$packageName.fileProvider", file,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            handler.post {
                try {
                    startActivity(intent)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("install", e.message, null)
                }
            }
        } catch (e: Exception) {
            handler.post { result.error("install", e.message, null) }
        }
    }

    /// A haptic by name, as the app's own (`selection`, `confirm`,
    /// `attention`, …); an unknown one does nothing.
    private fun haptic(kind: String) {
        val view: View = window?.decorView ?: return
        val sdk = Build.VERSION.SDK_INT
        when (kind) {
            "selection" -> view.performHapticFeedback(
                if (sdk >= 34) 26 else HapticFeedbackConstants.CLOCK_TICK,
            )
            "threshold" -> view.performHapticFeedback(
                if (sdk >= 34) 23 else HapticFeedbackConstants.CLOCK_TICK,
            )
            "toggleOn" -> view.performHapticFeedback(
                if (sdk >= 34) 21 else HapticFeedbackConstants.VIRTUAL_KEY,
            )
            "toggleOff" -> view.performHapticFeedback(
                if (sdk >= 34) 22 else HapticFeedbackConstants.CLOCK_TICK,
            )
            "settle" -> view.performHapticFeedback(
                if (sdk >= 30) 13 else HapticFeedbackConstants.CLOCK_TICK,
            )
            "confirm" -> view.performHapticFeedback(
                if (sdk >= 30) HapticFeedbackConstants.CONFIRM
                else HapticFeedbackConstants.VIRTUAL_KEY,
            )
            "reject" -> view.performHapticFeedback(
                if (sdk >= 30) HapticFeedbackConstants.REJECT
                else HapticFeedbackConstants.VIRTUAL_KEY,
            )
            "longPress" -> view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
            "attention" -> attention(view)
        }
    }

    /// The "attention" haptic: two short buzzes, where the platform has
    /// primitives for it; a plain tick where it does not.
    private fun attention(view: View) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R ||
            Settings.System.getInt(contentResolver, "haptic_feedback_enabled", 1) == 0
        ) {
            return
        }
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(VIBRATOR_MANAGER_SERVICE) as? android.os.VibratorManager)
                ?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            (getSystemService(VIBRATOR_SERVICE) as? android.os.Vibrator)
        } ?: return
        if (!vibrator.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_CLICK)) {
            view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
            return
        }
        val effect = VibrationEffect.startComposition()
            .addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 0.8f)
            .addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 0.6f, 90)
            .compose()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            vibrator.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(
                effect,
                android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_ALARM)
                    .build(),
            )
        }
    }
}
