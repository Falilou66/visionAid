package com.kangue.kangue_app

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
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
                    "isHandsFree" -> result.success(KangueBackgroundService.isHandsFree)
                    "triggerListen" -> {
                        sendServiceAction(KangueBackgroundService.ACTION_START_LISTENING)
                        result.success(true)
                    }
                    "startContinuous" -> {
                        // Ensure the service exists, then arm the hands-free loop.
                        startBgService()
                        sendServiceAction(KangueBackgroundService.ACTION_START_CONTINUOUS)
                        result.success(true)
                    }
                    "stopContinuous" -> {
                        sendServiceAction(KangueBackgroundService.ACTION_STOP_CONTINUOUS)
                        result.success(true)
                    }
                    "pauseListening" -> {
                        sendServiceAction(KangueBackgroundService.ACTION_PAUSE)
                        result.success(true)
                    }
                    "resumeListening" -> {
                        sendServiceAction(KangueBackgroundService.ACTION_RESUME)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── App launcher channel ────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kangue/launcher")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "launchApp" -> {
                        val name = call.argument<String>("name") ?: ""
                        val pkg = call.argument<String>("package")
                        result.success(launchApp(name, pkg))
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
                    "getScreenText"     -> result.success(KangueAccessibilityService.readActiveScreen())
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

        // ── Event channel: app-change announcements from a11y service → Flutter
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kangue/screen")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    KangueAccessibilityService.onScreenChanged = { appLabel ->
                        runOnUiThread { events?.success(appLabel) }
                    }
                }
                override fun onCancel(arguments: Any?) {
                    KangueAccessibilityService.onScreenChanged = null
                }
            })
    }

    /**
     * Launches an app, preferring the known [pkg] but falling back to matching an
     * installed app by its display label ([name]) — so voice commands like
     * "ouvre TikTok" work even when the hard-coded package is wrong or missing.
     * Returns false only when nothing could be resolved/launched.
     */
    private fun launchApp(name: String, pkg: String?): Boolean {
        val pm = packageManager
        // 1. Try the provided package directly.
        if (!pkg.isNullOrBlank()) {
            launchPackage(pm, pkg)?.let { startActivity(it); return true }
        }
        // 2. Fall back to resolving an installed app by its (localized) label.
        val query = name.lowercase().trim()
        if (query.isEmpty()) return false
        val apps = try {
            pm.getInstalledApplications(PackageManager.GET_META_DATA)
        } catch (_: Exception) {
            emptyList()
        }
        // Exact label match wins; otherwise the first launchable "contains" match.
        var contains: String? = null
        for (app in apps) {
            val label = pm.getApplicationLabel(app).toString().lowercase()
            if (label == query && launchPackage(pm, app.packageName) != null) {
                launchPackage(pm, app.packageName)?.let { startActivity(it); return true }
            }
            if (contains == null && (label.contains(query) || query.contains(label)) &&
                label.isNotBlank() && launchPackage(pm, app.packageName) != null
            ) {
                contains = app.packageName
            }
        }
        contains?.let { launchPackage(pm, it)?.let { i -> startActivity(i); return true } }
        return false
    }

    private fun launchPackage(pm: PackageManager, pkg: String): Intent? =
        pm.getLaunchIntentForPackage(pkg)?.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }

    private fun sendServiceAction(action: String) {
        val intent = Intent(this, KangueBackgroundService::class.java).apply {
            this.action = action
        }
        startService(intent)
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
