package com.kangue.kangue_app

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Background service channel ──────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kangue/background")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "init" -> {
                        val key = call.argument<String>("apiKey") ?: ""
                        prefs().edit().putString("groq_api_key", key).apply()
                        result.success(true)
                    }
                    "startService" -> {
                        startBgService()
                        result.success(true)
                    }
                    "stopService" -> {
                        stopService(Intent(this, KangueBackgroundService::class.java))
                        result.success(true)
                    }
                    "isRunning" -> result.success(KangueBackgroundService.isRunning)
                    "triggerListen" -> {
                        val intent = Intent(this, KangueBackgroundService::class.java)
                            .apply { action = KangueBackgroundService.ACTION_START_LISTENING }
                        startService(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Accessibility channel ───────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kangue/accessibility")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled"         -> result.success(isA11yEnabled())
                    "openSettings"      -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    }
                    "getScreenText"     -> result.success(KangueAccessibilityService.capturedScreenText)
                    "getCurrentPackage" -> result.success(KangueAccessibilityService.currentPackageName)
                    else                -> result.notImplemented()
                }
            }

        // ── Event channel: commands from background service → Flutter ───────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kangue/commands")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    KangueBackgroundService.onCommandReceived = { cmd ->
                        runOnUiThread { events?.success(cmd) }
                    }
                }
                override fun onCancel(arguments: Any?) {
                    KangueBackgroundService.onCommandReceived = null
                }
            })
    }

    private fun startBgService() {
        val intent = Intent(this, KangueBackgroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun isA11yEnabled(): Boolean {
        val am = getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        val enabled = am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
        return enabled.any { it.id.contains("com.kangue.kangue_app") }
    }

    private fun prefs() = getSharedPreferences("kangue_prefs", Context.MODE_PRIVATE)
}
