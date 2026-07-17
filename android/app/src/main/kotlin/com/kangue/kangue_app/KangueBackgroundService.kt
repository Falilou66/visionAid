package com.kangue.kangue_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer

/**
 * Foreground service that gives a visually-impaired user a fully **hands-free**
 * assistant: the microphone stays open in a continuous recognition loop, and any
 * phrase that starts with the wake word « Jarvis » is forwarded to Flutter as a
 * command (through [onCommandReceived], wired by [MainActivity] over the
 * `com.kangue/commands` event channel).
 *
 * Design notes:
 * - Android's [SpeechRecognizer] stops after every utterance/error, so we keep
 *   re-arming it in [scheduleListen]. This is the only way to get "always
 *   listening" on the SpeechRecognizer API.
 * - The recogniser would otherwise pick up Kangue's own text-to-speech and react
 *   to it (feedback loop). Flutter therefore calls [pauseListening] before
 *   speaking and [resumeListening] afterwards.
 * - A wake word ("jarvis" and common mishears) gates commands so ambient speech
 *   and background noise don't trigger actions.
 */
class KangueBackgroundService : Service() {

    companion object {
        @Volatile var isRunning: Boolean = false
            private set

        /** Whether the continuous hands-free loop is currently armed. */
        @Volatile var isHandsFree: Boolean = false
            private set

        const val ACTION_START_LISTENING = "com.kangue.action.START_LISTENING"
        const val ACTION_START_CONTINUOUS = "com.kangue.action.START_CONTINUOUS"
        const val ACTION_STOP_CONTINUOUS = "com.kangue.action.STOP_CONTINUOUS"
        const val ACTION_PAUSE = "com.kangue.action.PAUSE"
        const val ACTION_RESUME = "com.kangue.action.RESUME"
        const val ACTION_STOP = "com.kangue.action.STOP"

        private const val TAG = "KangueVoice"
        private const val CHANNEL_ID = "kangue_background"
        private const val NOTIFICATION_ID = 4201

        /** Delay before re-arming the recogniser, avoids ERROR_RECOGNIZER_BUSY. */
        private const val REARM_DELAY_MS = 600L

        /**
         * When only silence/errors come back we back off progressively so the mic
         * does not visibly flicker on/off several times a second. It stays snappy
         * as soon as real speech is heard (the counter resets in [onBeginningOfSpeech]).
         */
        private const val REARM_BACKOFF_MAX_MS = 4000L

        /**
         * Wake words that "open" a command. We include common French mishears of
         * "Jarvis" so the assistant still triggers when recognition is imperfect.
         */
        private val WAKE_WORDS = listOf(
            "jarvis", "jarvice", "jarvi", "djarvis", "charvis", "sarvis",
            "jervis", "harvis", "travis", "arvis", "jarvisse",
        )

        /** Set by MainActivity; receives recognised voice commands (wake word stripped). */
        var onCommandReceived: ((String) -> Unit)? = null

        /**
         * Extracts the command that follows the wake word. Returns:
         *  - the trimmed remainder if the phrase contains a wake word,
         *  - "" (empty) when a wake word is present but nothing follows it,
         *  - null when no wake word is present at all (phrase must be ignored).
         */
        fun extractCommand(raw: String): String? {
            val lower = raw.lowercase().trim()
            for (w in WAKE_WORDS) {
                val idx = lower.indexOf(w)
                if (idx >= 0) {
                    // Take everything after the matched wake word in the ORIGINAL text.
                    val after = raw.substring(idx + w.length)
                    return after.trimStart(' ', ',', '.', ':', ';', '!', '?').trim()
                }
            }
            return null
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var isListening = false

    /** Consecutive silent/failed passes; drives the re-arm backoff. */
    private var idleCycles = 0

    /** Mode of the current pass, read by the (reused) recognition listener. */
    private var currentSingleShot = false

    /** True while Kangue is speaking; the mic must not run then. */
    private var paused = false

    private val vibrator: Vibrator? by lazy {
        getSystemService(VIBRATOR_SERVICE) as? Vibrator
    }

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createChannel()
        startForegroundCompat(buildNotification("Kangue est prêt. Dites « Jarvis »."))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_LISTENING -> startSingleShot()
            ACTION_START_CONTINUOUS -> startContinuous()
            ACTION_STOP_CONTINUOUS -> stopContinuous()
            ACTION_PAUSE -> pauseListening()
            ACTION_RESUME -> resumeListening()
            ACTION_STOP -> stopSelf()
        }
        return START_STICKY
    }

    // ── Hands-free continuous loop ─────────────────────────────────────────────

    fun startContinuous() {
        Log.d(TAG, "startContinuous (already=$isHandsFree)")
        if (isHandsFree) return
        isHandsFree = true
        paused = false
        idleCycles = 0
        updateNotification("Écoute active. Dites « Jarvis » suivi de votre demande.")
        scheduleListen()
    }

    fun stopContinuous() {
        isHandsFree = false
        cancelRecognizer()
        updateNotification("Écoute en pause. Appuyez sur Parler.")
    }

    /** Called by Flutter before speaking so the mic doesn't hear the TTS. */
    fun pauseListening() {
        paused = true
        cancelRecognizer()
    }

    /** Called by Flutter once it has finished speaking. */
    fun resumeListening() {
        paused = false
        idleCycles = 0
        if (isHandsFree) scheduleListen()
    }

    /** One manual listening pass triggered by the "Parler" notification action. */
    private fun startSingleShot() {
        if (!isHandsFree) {
            // Behave like a temporary hands-free window: listen once.
            paused = false
            beginRecognition(singleShot = true)
        } else {
            scheduleListen()
        }
    }

    private fun scheduleListen() {
        if (!isHandsFree || paused || isListening) return
        mainHandler.removeCallbacks(rearmRunnable)
        // Grow the gap between mic passes while nothing is heard (600ms → 4s),
        // so the mic indicator stops flickering during long silences.
        val delay = (REARM_DELAY_MS * (idleCycles + 1)).coerceAtMost(REARM_BACKOFF_MAX_MS)
        mainHandler.postDelayed(rearmRunnable, delay)
    }

    private val rearmRunnable = Runnable { beginRecognition(singleShot = false) }

    private fun beginRecognition(singleShot: Boolean) {
        if (isListening) return
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            updateNotification("Reconnaissance vocale indisponible.")
            return
        }
        isListening = true
        currentSingleShot = singleShot
        if (isHandsFree && !paused) updateNotification("J'écoute… dites « Jarvis ».")
        else updateNotification("Je vous écoute…")
        // Reuse a single recogniser instead of destroying/recreating it every pass:
        // recreating it each cycle re-runs the async service bind and was racing
        // startListening() → "not connected to the recognition service".
        if (recognizer == null) {
            recognizer = SpeechRecognizer.createSpeechRecognizer(this).apply {
                setRecognitionListener(makeListener())
            }
        }
        val recognizerIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "fr_FR")
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "fr")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            // NOTE: intentionally NOT forcing EXTRA_PREFER_OFFLINE — on the A5s the
            // French offline model is absent, so the recogniser refused to connect.
            // The device has network (the online recogniser binds fine).
        }
        // Give the freshly-created recogniser a moment to bind to the system
        // recognition service before starting, otherwise startListening() throws
        // "not connected to the recognition service" on this device.
        val target = recognizer
        mainHandler.postDelayed({
            if (!isListening || target == null) return@postDelayed
            try {
                Log.d(TAG, "startListening (singleShot=$currentSingleShot, handsFree=$isHandsFree)")
                target.startListening(recognizerIntent)
            } catch (e: Exception) {
                Log.e(TAG, "startListening threw: ${e.message}")
                isListening = false
                dropRecognizer()
                scheduleListen()
            }
        }, 250L)
    }

    private fun cancelRecognizer() {
        mainHandler.removeCallbacks(rearmRunnable)
        isListening = false
        dropRecognizer()
    }

    /** Destroys and forgets the recogniser so the next pass creates a fresh one. */
    private fun dropRecognizer() {
        recognizer?.let {
            try { it.cancel() } catch (_: Exception) {}
            try { it.destroy() } catch (_: Exception) {}
        }
        recognizer = null
    }

    private fun makeListener() = object : RecognitionListener {
        override fun onResults(results: Bundle?) {
            isListening = false
            val text = results
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                ?.trim()
                .orEmpty()
            Log.d(TAG, "onResults text='$text' -> command=${extractCommand(text)}")

            if (currentSingleShot) {
                // Manual "Parler": treat the whole phrase as a command, no wake word.
                if (text.isNotEmpty()) dispatchCommand(text)
                else updateNotification("Rien entendu. Dites « Jarvis ».")
                if (isHandsFree) scheduleListen()
                return
            }

            val command = if (text.isNotEmpty()) extractCommand(text) else null
            when {
                command == null -> {
                    // No wake word: ignore silently and keep listening.
                    scheduleListen()
                }
                command.isEmpty() -> {
                    // Just "Kangue": acknowledge and keep listening.
                    dispatchCommand("__wake__")
                    scheduleListen()
                }
                else -> {
                    dispatchCommand(command)
                    // Flutter pauses us while it processes/speaks; it resumes after.
                    scheduleListen()
                }
            }
        }

        override fun onError(error: Int) {
            Log.d(TAG, "onError code=$error")
            isListening = false
            // Connection/busy errors mean the reused recogniser is unusable —
            // throw it away so the next pass rebinds a fresh one.
            if (error == SpeechRecognizer.ERROR_CLIENT ||
                error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY ||
                error == SpeechRecognizer.ERROR_SERVER
            ) {
                dropRecognizer()
            }
            if (currentSingleShot && !isHandsFree) {
                updateNotification("Appuyez sur Parler pour réessayer.")
                return
            }
            // Silence/no-match/timeout are normal: back off so the mic stops
            // flickering. Reset backoff was already handled by onBeginningOfSpeech
            // if the user actually spoke.
            idleCycles++
            scheduleListen()
        }

        override fun onReadyForSpeech(params: Bundle?) {}

        /** Real speech detected → stay snappy on the next pass. */
        override fun onBeginningOfSpeech() { idleCycles = 0 }
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onPartialResults(partialResults: Bundle?) {}
        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private fun dispatchCommand(command: String) {
        Log.d(TAG, "dispatchCommand '$command' (listener set=${onCommandReceived != null})")
        vibrate()
        if (command != "__wake__") updateNotification("Vous : $command")
        mainHandler.post { onCommandReceived?.invoke(command) }
    }

    private fun vibrate() {
        val v = vibrator ?: return
        if (!v.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            v.vibrate(VibrationEffect.createOneShot(60, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION") v.vibrate(60)
        }
    }

    // ── Notification ──────────────────────────────────────────────────────────

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Kangue – Écoute",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Service d'écoute vocale en arrière-plan" }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        val talkIntent = Intent(this, KangueBackgroundService::class.java).apply {
            action = ACTION_START_LISTENING
        }
        val toggleIntent = Intent(this, KangueBackgroundService::class.java).apply {
            action = if (isHandsFree) ACTION_STOP_CONTINUOUS else ACTION_START_CONTINUOUS
        }
        val stopIntent = Intent(this, KangueBackgroundService::class.java).apply {
            action = ACTION_STOP
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val talkPending = PendingIntent.getService(this, 1, talkIntent, flags)
        val togglePending = PendingIntent.getService(this, 3, toggleIntent, flags)
        val stopPending = PendingIntent.getService(this, 2, stopIntent, flags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("Kangue")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_btn_speak_now, "Parler", talkPending,
                ).build(),
            )
            .addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_lock_idle_alarm,
                    if (isHandsFree) "Pause micro" else "Mains libres",
                    togglePending,
                ).build(),
            )
            .addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_menu_close_clear_cancel, "Arrêter", stopPending,
                ).build(),
            )
            .build()
    }

    private fun updateNotification(text: String) {
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification(text))
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    override fun onDestroy() {
        isRunning = false
        isHandsFree = false
        cancelRecognizer()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
