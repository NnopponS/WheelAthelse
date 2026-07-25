package com.wheelathlete.wheelathlete

import android.media.AudioManager
import android.media.ToneGenerator
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val cueChannel = "wheelathlete/countdown_cue"

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
                window.decorView.postDelayed({ generator.release() }, durationMs.toLong() + 100L)
                result.success(null)
            }
    }
}
