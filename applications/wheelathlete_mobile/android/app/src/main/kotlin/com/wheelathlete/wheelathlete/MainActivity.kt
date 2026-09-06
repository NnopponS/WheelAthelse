package com.wheelathlete.wheelathlete

import android.content.Intent
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val cueChannel = "wheelathlete/countdown_cue"
    private val updateChannel = "wheelathlete/app_update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, cueChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "play") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val requested = call.argument<Int>("durationMs") ?: 150
                val durationMs = requested.coerceIn(50, 1000)
                val isStart = call.argument<Boolean>("isStart") ?: false
                val tone = if (isStart) {
                    ToneGenerator.TONE_PROP_ACK
                } else {
                    ToneGenerator.TONE_PROP_BEEP
                }
                val generator = ToneGenerator(AudioManager.STREAM_MUSIC, 90)
                generator.startTone(tone, durationMs)
                window.decorView.postDelayed(
                    { generator.release() },
                    durationMs.toLong() + 100L,
                )
                result.success(null)
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallPackages" -> {
                        val allowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls()
                        result.success(allowed)
                    }

                    "openInstallPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            )
                            startActivity(intent)
                        }
                        result.success(null)
                    }

                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("BAD_APK", "APK path is missing", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val updateRoot = File(cacheDir, "wheelathlete_updates").canonicalFile
                            val apk = File(path).canonicalFile
                            val rootPrefix = updateRoot.path + File.separator
                            if (!apk.path.startsWith(rootPrefix) ||
                                !apk.name.lowercase().endsWith(".apk") ||
                                !apk.isFile
                            ) {
                                result.error(
                                    "BAD_APK",
                                    "APK is outside WheelAthlete's verified update cache",
                                    null,
                                )
                                return@setMethodCallHandler
                            }
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.update.provider",
                                apk,
                            )
                            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(installIntent)
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("INSTALL_FAILED", error.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
