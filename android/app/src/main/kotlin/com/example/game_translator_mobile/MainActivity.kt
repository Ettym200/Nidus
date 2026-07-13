package com.example.game_translator_mobile

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "game_translator/overlay"
    private val LIVE_EVENTS = "game_translator/live_audio"
    private val REQ_OVERLAY = 101
    private val REQ_PROJECTION = 102
    private val REQ_LIVE_PROJECTION = 103

    private var mediaProjectionManager: MediaProjectionManager? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingAction: String? = null

    private var projectionResultCode = 0
    private var projectionData: Intent? = null

    private var liveEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        mediaProjectionManager =
            getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, LIVE_EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    liveEventSink = events
                    LiveAudioService.chunkListener = { path ->
                        runOnUiThread {
                            liveEventSink?.success(mapOf("type" to "chunk", "path" to path))
                        }
                    }
                    LiveAudioService.statusListener = { status ->
                        runOnUiThread {
                            liveEventSink?.success(mapOf("type" to "status", "message" to status))
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    liveEventSink = null
                    LiveAudioService.chunkListener = null
                    LiveAudioService.statusListener = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkOverlayPermission" -> {
                        result.success(Settings.canDrawOverlays(this))
                    }
                    "requestOverlayPermission" -> {
                        if (Settings.canDrawOverlays(this)) {
                            result.success(true)
                        } else {
                            pendingResult = result
                            pendingAction = "overlay"
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            startActivityForResult(intent, REQ_OVERLAY)
                        }
                    }
                    "startOverlay" -> {
                        val apiKey = call.argument<String>("apiKey") ?: ""
                        val provider = call.argument<String>("provider") ?: "openai"
                        val model = call.argument<String>("model") ?: ""
                        val language = call.argument<String>("language") ?: "Português"
                        val customUrl = call.argument<String>("customUrl") ?: ""
                        val overlayStyle = call.argument<String>("overlayStyle") ?: "dark"

                        if (!Settings.canDrawOverlays(this)) {
                            result.error("NO_PERMISSION", "Permissão de overlay não concedida", null)
                            return@setMethodCallHandler
                        }

                        if (projectionData == null) {
                            pendingResult = result
                            pendingAction = "startOverlay"
                            getSharedPreferences("overlay_params", Context.MODE_PRIVATE).edit()
                                .putString("apiKey", apiKey)
                                .putString("provider", provider)
                                .putString("model", model)
                                .putString("language", language)
                                .putString("customUrl", customUrl)
                                .putString("overlayStyle", overlayStyle)
                                .apply()
                            startActivityForResult(
                                mediaProjectionManager!!.createScreenCaptureIntent(),
                                REQ_PROJECTION
                            )
                        } else {
                            launchOverlayService(apiKey, provider, model, language, customUrl, overlayStyle)
                            result.success(true)
                        }
                    }
                    "stopOverlay" -> {
                        stopService(Intent(this, OverlayService::class.java))
                        projectionData = null
                        projectionResultCode = 0
                        result.success(true)
                    }
                    "isOverlayRunning" -> {
                        @Suppress("DEPRECATION")
                        val am = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                        val running = am.getRunningServices(Int.MAX_VALUE)
                            .any { it.service.className == OverlayService::class.java.name }
                        result.success(running)
                    }
                    "startLiveAudio" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                            result.error("UNSUPPORTED", "Áudio interno requer Android 10+", null)
                            return@setMethodCallHandler
                        }
                        // Sempre pede captura fresca para o Live (não reutiliza a do overlay)
                        pendingResult = result
                        pendingAction = "startLiveAudio"
                        startActivityForResult(
                            mediaProjectionManager!!.createScreenCaptureIntent(),
                            REQ_LIVE_PROJECTION
                        )
                    }
                    "stopLiveAudio" -> {
                        val stop = Intent(this, LiveAudioService::class.java).apply {
                            action = LiveAudioService.ACTION_STOP
                        }
                        startService(stop)
                        stopService(Intent(this, LiveAudioService::class.java))
                        FloatingTranslationOverlay.hide()
                        result.success(true)
                    }
                    "showFloatingTranslation" -> {
                        val text = call.argument<String>("text") ?: ""
                        val style = call.argument<String>("style") ?: "dark"
                        if (text.isBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        if (!Settings.canDrawOverlays(this)) {
                            result.error("NO_PERMISSION", "Permissão de overlay necessária", null)
                            return@setMethodCallHandler
                        }
                        FloatingTranslationOverlay.show(this, text, style)
                        result.success(true)
                    }
                    "hideFloatingTranslation" -> {
                        FloatingTranslationOverlay.hide()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun launchOverlayService(
        apiKey: String, provider: String, model: String,
        language: String, customUrl: String, overlayStyle: String
    ) {
        val intent = Intent(this, OverlayService::class.java).apply {
            putExtra("apiKey", apiKey)
            putExtra("provider", provider)
            putExtra("model", model)
            putExtra("language", language)
            putExtra("customUrl", customUrl)
            putExtra("overlayStyle", overlayStyle)
            putExtra("resultCode", projectionResultCode)
            putExtra("projectionData", projectionData)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun launchLiveAudioService(resultCode: Int, data: Intent) {
        val intent = Intent(this, LiveAudioService::class.java).apply {
            putExtra("resultCode", resultCode)
            putExtra("projectionData", data)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        when (requestCode) {
            REQ_OVERLAY -> {
                val granted = Settings.canDrawOverlays(this)
                pendingResult?.success(granted)
                pendingResult = null
            }
            REQ_PROJECTION -> {
                if (resultCode == Activity.RESULT_OK && data != null) {
                    projectionResultCode = resultCode
                    projectionData = data

                    if (pendingAction == "startOverlay") {
                        val prefs = getSharedPreferences("overlay_params", Context.MODE_PRIVATE)
                        launchOverlayService(
                            prefs.getString("apiKey", "") ?: "",
                            prefs.getString("provider", "openai") ?: "openai",
                            prefs.getString("model", "") ?: "",
                            prefs.getString("language", "Português") ?: "Português",
                            prefs.getString("customUrl", "") ?: "",
                            prefs.getString("overlayStyle", "dark") ?: "dark"
                        )
                        pendingResult?.success(true)
                    }
                } else {
                    pendingResult?.error("PERMISSION_DENIED", "Permissão de captura negada", null)
                }
                pendingResult = null
                pendingAction = null
            }
            REQ_LIVE_PROJECTION -> {
                if (resultCode == Activity.RESULT_OK && data != null) {
                    launchLiveAudioService(resultCode, data)
                    pendingResult?.success(true)
                } else {
                    pendingResult?.error("PERMISSION_DENIED", "Permissão de captura negada", null)
                }
                pendingResult = null
                pendingAction = null
            }
        }
    }
}
