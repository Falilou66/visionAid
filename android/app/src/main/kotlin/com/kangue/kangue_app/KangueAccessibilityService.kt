package com.kangue.kangue_app

import android.accessibilityservice.AccessibilityService
import android.content.pm.PackageManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Watches the foreground app for a visually-impaired user.
 *
 * On every window change it **vibrates** (event feedback) and, when the user
 * switches to a *different* app, **announces the app name** through
 * [onScreenChanged] so Flutter can speak it. The full screen text is still read
 * only **on demand** via [readActiveScreen] — walking the whole node tree on
 * every event floods the main thread (Chrome fires a storm of content-change
 * events) and caused ANRs, so that stays lazy.
 */
class KangueAccessibilityService : AccessibilityService() {

    companion object {
        /** The running service instance, used for on-demand screen reads. */
        @Volatile private var instance: KangueAccessibilityService? = null

        /** Package name of the last external app seen in the foreground. */
        @Volatile var currentPackageName: String = ""
            private set

        /** Set by MainActivity; receives the human name of a newly-opened app. */
        var onScreenChanged: ((String) -> Unit)? = null

        /**
         * Packages that must never be treated as the "screen to read" nor
         * announced: Kangue itself, the system UI, and the voice-recognition
         * overlay shown while the user is dictating a command.
         */
        private val IGNORED_PACKAGES = setOf(
            "com.android.systemui",
            "com.google.android.googlequicksearchbox",
        )

        /**
         * Walks the current foreground window and returns its visible text.
         * Runs only when explicitly requested, so it never floods the main
         * thread. Returns "" if the service isn't connected or the foreground
         * is Kangue itself.
         */
        fun readActiveScreen(): String {
            val svc = instance ?: return ""
            val root = svc.rootInActiveWindow ?: return ""
            val pkg = root.packageName?.toString()
            if (pkg == null || pkg == svc.packageName || pkg in IGNORED_PACKAGES) return ""
            val builder = StringBuilder()
            svc.collectText(root, builder)
            return builder.toString().trim().take(8000)
        }

        /** Kept for API compatibility: the last text captured on demand. */
        @Volatile var capturedScreenText: String = ""
            private set
    }

    /** Package we last announced, so we only announce on real app switches. */
    private var lastAnnouncedPackage: String = ""

    private val vibrator: Vibrator? by lazy {
        getSystemService(VIBRATOR_SERVICE) as? Vibrator
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Deliberately cheap: no tree walk here (that's lazy in readActiveScreen).
        event ?: return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName || pkg in IGNORED_PACKAGES) return

        // Vibrate on every window change so the user feels "something happened".
        vibrate()

        currentPackageName = pkg
        if (pkg != lastAnnouncedPackage) {
            lastAnnouncedPackage = pkg
            val label = appLabel(pkg)
            onScreenChanged?.invoke(label)
        }
    }

    private fun appLabel(pkg: String): String {
        return try {
            val pm = packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
        } catch (_: PackageManager.NameNotFoundException) {
            pkg
        }
    }

    private fun vibrate() {
        val v = vibrator ?: return
        if (!v.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            v.vibrate(VibrationEffect.createOneShot(40, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION") v.vibrate(40)
        }
    }

    private fun collectText(node: AccessibilityNodeInfo?, out: StringBuilder) {
        node ?: return
        if (out.length >= 8000) return
        node.text?.let {
            val t = it.toString().trim()
            if (t.isNotEmpty()) out.append(t).append('\n')
        }
        if (node.text.isNullOrBlank()) {
            node.contentDescription?.let {
                val t = it.toString().trim()
                if (t.isNotEmpty()) out.append(t).append('\n')
            }
        }
        for (i in 0 until node.childCount) {
            collectText(node.getChild(i), out)
        }
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        if (instance === this) instance = null
        onScreenChanged = null
        super.onDestroy()
    }
}
