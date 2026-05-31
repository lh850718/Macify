package com.huxizen.huxi_zen

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import java.io.File
import org.json.JSONArray
import org.json.JSONObject

class BackgroundAudioService : MediaSessionService() {
    private val handler = Handler(Looper.getMainLooper())
    private val channels = linkedMapOf<String, AudioChannel>()
    private var mediaSession: MediaSession? = null
    private var mediaSessionChannelId = ""
    private var hapticPattern: HapticPattern? = null
    private var hapticPhaseIndex = 0
    private var hapticCompletedCycles = 0
    private var hapticRunnable: Runnable? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START,
            ACTION_SYNC,
            -> handleSync(intent.getStringExtra(EXTRA_TRACKS_JSON).orEmpty())

            ACTION_STOP -> {
                handleStop()
                return START_NOT_STICKY
            }

            ACTION_HAPTICS_START -> handleStartHaptics(
                intent.getStringExtra(EXTRA_HAPTIC_PATTERN_JSON).orEmpty(),
            )

            ACTION_HAPTICS_STOP -> handleStopHaptics()
        }
        return super.onStartCommand(intent, flags, startId)
    }

    override fun onGetSession(
        controllerInfo: MediaSession.ControllerInfo,
    ): MediaSession? = mediaSession

    override fun onDestroy() {
        stopHapticPattern()
        releasePlayback()
        super.onDestroy()
    }

    private fun handleSync(tracksJson: String) {
        val tracks = TrackSpec.fromJsonArray(tracksJson)
        if (tracks.isEmpty()) {
            updateStatus(running = false, trackCount = 0, lastCommand = "sync-empty")
            handleStop()
            return
        }

        val desired = tracks.associateBy { it.channelId }

        for (track in tracks) {
            val existing = channels[track.channelId]
            if (existing == null) {
                channels[track.channelId] = AudioChannel(track).also { it.start() }
            } else {
                existing.update(track)
            }
        }

        val removedIds = channels.keys
            .filter { !desired.containsKey(it) }
            .toList()
        for (channelId in removedIds) {
            val channel = channels.remove(channelId) ?: continue
            channel.fadeOutAndRelease()
        }

        ensureMediaSession()
        updateStatus(
            running = channels.isNotEmpty(),
            trackCount = channels.size,
            lastCommand = "sync",
            primaryUri = channels.values.firstOrNull()?.track?.uri.orEmpty(),
            playbackState = channels.values.firstOrNull()?.playbackStateName().orEmpty(),
            activeChannelIds = channels.keys.toList(),
        )
    }

    private fun handleStop() {
        stopHapticPattern()
        releasePlayback()
        updateStatus(
            running = false,
            trackCount = 0,
            lastCommand = "stop",
            hapticsRunning = false,
            hapticPatternId = "",
            hapticPhase = "",
            hapticPhaseIndex = -1,
        )
        stopSelf()
    }

    private fun handleStartHaptics(patternJson: String) {
        val pattern = HapticPattern.fromJson(patternJson)
        if (pattern == null) {
            updateStatus(
                running = channels.isNotEmpty(),
                trackCount = channels.size,
                lastCommand = "haptics-error",
                lastError = "invalid-haptic-pattern",
                activeChannelIds = channels.keys.toList(),
                hapticsRunning = false,
                hapticPatternId = "",
                hapticPhase = "",
                hapticPhaseIndex = -1,
            )
            return
        }

        hapticPattern = pattern
        hapticPhaseIndex = 0
        hapticCompletedCycles = 0
        scheduleHapticPhase()
    }

    private fun handleStopHaptics() {
        stopHapticPattern()
        updateStatus(
            running = channels.isNotEmpty(),
            trackCount = channels.size,
            lastCommand = "haptics-stop",
            activeChannelIds = channels.keys.toList(),
            hapticsRunning = false,
            hapticPatternId = "",
            hapticPhase = "",
            hapticPhaseIndex = -1,
        )
        if (channels.isEmpty()) stopSelf()
    }

    private fun ensureMediaSession() {
        val primary = channels.values.firstOrNull { it.currentPlayer != null }
            ?: return
        if (mediaSession != null && mediaSessionChannelId == primary.track.channelId) {
            return
        }

        mediaSession?.release()
        mediaSession = primary.currentPlayer?.let { player ->
            mediaSessionChannelId = primary.track.channelId
            MediaSession.Builder(this, player).build()
        }
    }

    private fun releasePlayback() {
        mediaSession?.release()
        mediaSession = null
        mediaSessionChannelId = ""

        for (channel in channels.values) {
            channel.releaseNow()
        }
        channels.clear()
    }

    private fun scheduleHapticPhase() {
        val pattern = hapticPattern ?: return
        if (pattern.phases.isEmpty()) {
            stopHapticPattern()
            return
        }
        hapticRunnable?.let { handler.removeCallbacks(it) }

        val boundedIndex = hapticPhaseIndex.coerceIn(0, pattern.phases.lastIndex)
        hapticPhaseIndex = boundedIndex
        val phase = pattern.phases[boundedIndex]
        if (phase.vibrateMs > 0) {
            pulseHaptic(phase.vibrateMs, phase.amplitude)
        }
        updateStatus(
            running = channels.isNotEmpty(),
            trackCount = channels.size,
            lastCommand = "haptic-phase",
            primaryUri = channels.values.firstOrNull()?.track?.uri.orEmpty(),
            playbackState = channels.values.firstOrNull()?.playbackStateName().orEmpty(),
            activeChannelIds = channels.keys.toList(),
            hapticsRunning = true,
            hapticPatternId = pattern.patternId,
            hapticPhase = phase.label,
            hapticPhaseIndex = boundedIndex,
        )

        hapticRunnable = Runnable {
            val nextIndex = hapticPhaseIndex + 1
            if (nextIndex <= pattern.phases.lastIndex) {
                hapticPhaseIndex = nextIndex
                scheduleHapticPhase()
                return@Runnable
            }
            hapticCompletedCycles += 1
            val shouldRepeat = pattern.repeat &&
                (pattern.cycles <= 0 || hapticCompletedCycles < pattern.cycles)
            if (shouldRepeat) {
                hapticPhaseIndex = 0
                scheduleHapticPhase()
                return@Runnable
            }
            stopHapticPattern()
            updateStatus(
                running = channels.isNotEmpty(),
                trackCount = channels.size,
                lastCommand = "haptics-complete",
                activeChannelIds = channels.keys.toList(),
                hapticsRunning = false,
                hapticPatternId = "",
                hapticPhase = "",
                hapticPhaseIndex = -1,
            )
        }.also {
            handler.postDelayed(it, phase.durationMs.coerceAtLeast(1).toLong())
        }
    }

    private fun stopHapticPattern() {
        hapticRunnable?.let { handler.removeCallbacks(it) }
        hapticRunnable = null
        hapticPattern = null
        hapticPhaseIndex = 0
        hapticCompletedCycles = 0
    }

    private fun pulseHaptic(durationMs: Int, amplitude: Int) {
        val vibrator = vibrator() ?: return
        if (!vibrator.hasVibrator()) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(
                    VibrationEffect.createOneShot(
                        durationMs.coerceIn(1, 1000).toLong(),
                        amplitude.coerceIn(1, 255),
                    ),
                )
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(durationMs.coerceIn(1, 1000).toLong())
            }
        } catch (_: SecurityException) {
            updateStatus(
                running = channels.isNotEmpty(),
                trackCount = channels.size,
                lastCommand = "haptics-error",
                lastError = "missing-vibrate-permission",
                activeChannelIds = channels.keys.toList(),
            )
        }
    }

    private fun vibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Vibrator::class.java)
        }
    }

    private fun buildPlayer(track: TrackSpec, initialVolume: Float): ExoPlayer {
        return ExoPlayer.Builder(this).build().apply {
            addListener(playerListener(track))
            setWakeMode(C.WAKE_MODE_LOCAL)
            repeatMode = Player.REPEAT_MODE_OFF
            volume = initialVolume.coerceIn(0f, 1f)
            setMediaItem(mediaItem(track))
            prepare()
            playWhenReady = true
        }
    }

    private fun mediaItem(track: TrackSpec): MediaItem {
        return MediaItem.Builder()
            .setMediaId(track.mediaId.ifBlank { track.uri })
            .setUri(track.normalizedUri())
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(track.title.ifBlank { track.mediaId })
                    .build(),
            )
            .build()
    }

    private fun playerListener(track: TrackSpec): Player.Listener {
        return object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                val primary = channels.values.firstOrNull()
                updateStatus(
                    running = channels.isNotEmpty(),
                    trackCount = channels.size,
                    lastCommand = "playback-state",
                    primaryUri = primary?.track?.uri ?: track.uri,
                    playbackState = primary?.playbackStateName()
                        ?: playbackStateName(playbackState),
                    activeChannelIds = channels.keys.toList(),
                )
            }

            override fun onPlayerError(error: PlaybackException) {
                updateStatus(
                    running = channels.isNotEmpty(),
                    trackCount = channels.size,
                    lastCommand = "player-error",
                    primaryUri = track.uri,
                    playbackState = "error",
                    lastError = error.errorCodeName,
                    activeChannelIds = channels.keys.toList(),
                )
            }
        }
    }

    private fun playbackStateName(playbackState: Int): String {
        return when (playbackState) {
            Player.STATE_BUFFERING -> "buffering"
            Player.STATE_ENDED -> "ended"
            Player.STATE_IDLE -> "idle"
            Player.STATE_READY -> "ready"
            else -> "unknown"
        }
    }

    private inner class AudioChannel(initialTrack: TrackSpec) {
        var track = initialTrack
            private set
        var currentPlayer: ExoPlayer? = null
            private set
        private var nextPlayer: ExoPlayer? = null
        private var loopRunnable: Runnable? = null
        private val fadeRunnables = mutableMapOf<ExoPlayer, Runnable>()
        private var disposed = false
        private var startingLoop = false

        fun start() {
            if (disposed || currentPlayer != null) return
            currentPlayer = buildPlayer(track, initialVolume = 0f)
            currentPlayer?.let { attachLoopFallback(it) }
            fade(
                player = currentPlayer ?: return,
                to = track.volume,
                durationMs = SWITCH_FADE_MS,
            )
            scheduleLoop()
        }

        fun update(nextTrack: TrackSpec) {
            val uriChanged = nextTrack.uri != track.uri
            track = nextTrack
            if (uriChanged) {
                replaceWith(nextTrack)
                return
            }

            for (player in listOfNotNull(currentPlayer, nextPlayer)) {
                fade(player = player, to = track.volume, durationMs = SWITCH_FADE_MS)
            }
            scheduleLoop()
        }

        fun fadeOutAndRelease() {
            if (disposed) return
            disposed = true
            cancelLoop()
            val players = listOfNotNull(currentPlayer, nextPlayer)
            currentPlayer = null
            nextPlayer = null
            if (players.isEmpty()) return
            for (player in players) {
                fade(
                    player = player,
                    to = 0f,
                    durationMs = SWITCH_FADE_MS,
                    releaseOnComplete = true,
                )
            }
        }

        fun releaseNow() {
            disposed = true
            cancelLoop()
            for ((player, runnable) in fadeRunnables) {
                handler.removeCallbacks(runnable)
                player.release()
            }
            fadeRunnables.clear()
            currentPlayer?.release()
            currentPlayer = null
            nextPlayer?.release()
            nextPlayer = null
        }

        fun playbackStateName(): String {
            return playbackStateName(currentPlayer?.playbackState ?: Player.STATE_IDLE)
        }

        private fun replaceWith(nextTrack: TrackSpec) {
            cancelLoop()
            val oldPlayers = listOfNotNull(currentPlayer, nextPlayer)
            currentPlayer = null
            nextPlayer = null
            for (player in oldPlayers) {
                fade(
                    player = player,
                    to = 0f,
                    durationMs = SWITCH_FADE_MS,
                    releaseOnComplete = true,
                )
            }
            track = nextTrack
            start()
        }

        private fun scheduleLoop() {
            cancelLoop()
            if (disposed || currentPlayer == null) return
            if (track.durationMs <= 0) return

            val positionMs = currentPlayer?.currentPosition?.coerceAtLeast(0L) ?: 0L
            val remainingMs = (track.durationMs.toLong() - positionMs).coerceAtLeast(0L)
            val delayMs = (remainingMs - LOOP_FADE_MS)
                .takeIf { it > 0 }
                ?: 0L
            loopRunnable = Runnable { startLoopCrossfade() }.also {
                handler.postDelayed(it, delayMs)
            }
        }

        private fun cancelLoop() {
            loopRunnable?.let { handler.removeCallbacks(it) }
            loopRunnable = null
        }

        private fun startLoopCrossfade() {
            if (disposed || currentPlayer == null || nextPlayer != null || startingLoop) {
                return
            }
            startingLoop = true
            val next = buildPlayer(track, initialVolume = 0f)
            attachLoopFallback(next)
            startingLoop = false
            if (disposed) {
                next.release()
                return
            }

            val previous = currentPlayer
            nextPlayer = next
            if (previous != null) {
                fade(
                    player = previous,
                    to = 0f,
                    durationMs = LOOP_FADE_MS,
                    releaseOnComplete = true,
                )
            }
            fade(
                player = next,
                to = track.volume,
                durationMs = LOOP_FADE_MS,
                onComplete = {
                    if (!disposed) {
                        currentPlayer = next
                        nextPlayer = null
                        ensureMediaSession()
                        scheduleLoop()
                    }
                },
            )
        }

        private fun attachLoopFallback(player: ExoPlayer) {
            player.addListener(
                object : Player.Listener {
                    override fun onPlaybackStateChanged(playbackState: Int) {
                        if (playbackState == Player.STATE_ENDED &&
                            !disposed &&
                            player == currentPlayer
                        ) {
                            startLoopCrossfade()
                        }
                    }
                },
            )
        }

        private fun fade(
            player: ExoPlayer,
            to: Float,
            durationMs: Int,
            releaseOnComplete: Boolean = false,
            onComplete: (() -> Unit)? = null,
        ) {
            fadeRunnables[player]?.let { handler.removeCallbacks(it) }
            val from = player.volume
            val target = to.coerceIn(0f, 1f)
            val startedAt = SystemClock.elapsedRealtime()
            val totalMs = durationMs.coerceAtLeast(1).toLong()

            lateinit var runnable: Runnable
            runnable = object : Runnable {
                override fun run() {
                    val elapsedMs = SystemClock.elapsedRealtime() - startedAt
                    val progress = (elapsedMs.toFloat() / totalMs).coerceIn(0f, 1f)
                    player.volume = from + ((target - from) * progress)

                    if (progress >= 1f) {
                        fadeRunnables.remove(player)
                        player.volume = target
                        if (releaseOnComplete) {
                            player.release()
                        }
                        onComplete?.invoke()
                        return
                    }
                    handler.postDelayed(this, FADE_TICK_MS.toLong())
                }
            }
            fadeRunnables[player] = runnable
            handler.post(runnable)
        }
    }

    private data class TrackSpec(
        val channelId: String,
        val mediaId: String,
        val title: String,
        val uri: String,
        val durationMs: Int,
        val volume: Float,
    ) {
        fun normalizedUri(): Uri {
            return when {
                uri.startsWith("asset:///") -> Uri.parse(uri)
                uri.startsWith("assets/") -> Uri.parse("asset:///flutter_assets/$uri")
                uri.startsWith("http://") || uri.startsWith("https://") -> Uri.parse(uri)
                uri.startsWith("/") -> Uri.fromFile(File(uri))
                else -> Uri.parse(uri)
            }
        }

        companion object {
            fun fromJsonArray(raw: String): List<TrackSpec> {
                if (raw.isBlank()) return emptyList()
                return try {
                    val array = JSONArray(raw)
                    buildList {
                        for (index in 0 until array.length()) {
                            val item = array.optJSONObject(index) ?: continue
                            val spec = fromJson(item)
                            if (spec.uri.isNotBlank()) add(spec)
                        }
                    }
                } catch (_: Exception) {
                    emptyList()
                }
            }

            private fun fromJson(item: JSONObject): TrackSpec {
                val mediaId = item.optString("mediaId")
                val channelId = item.optString("channelId")
                    .ifBlank { mediaId }
                    .ifBlank { item.optString("uri") }
                return TrackSpec(
                    channelId = channelId,
                    mediaId = mediaId,
                    title = item.optString("title"),
                    uri = item.optString("uri"),
                    durationMs = item.optInt("durationMs", 0),
                    volume = item.optDouble("volume", 1.0).toFloat(),
                )
            }
        }
    }

    private data class HapticPattern(
        val patternId: String,
        val repeat: Boolean,
        val cycles: Int,
        val phases: List<HapticPhase>,
    ) {
        companion object {
            fun fromJson(raw: String): HapticPattern? {
                if (raw.isBlank()) return null
                return try {
                    val json = JSONObject(raw)
                    val phasesJson = json.optJSONArray("phases") ?: JSONArray()
                    val phases = buildList {
                        for (index in 0 until phasesJson.length()) {
                            val item = phasesJson.optJSONObject(index) ?: continue
                            val phase = HapticPhase.fromJson(item)
                            if (phase.durationMs > 0) add(phase)
                        }
                    }
                    if (phases.isEmpty()) return null
                    HapticPattern(
                        patternId = json.optString("patternId").ifBlank {
                            "haptic-pattern"
                        },
                        repeat = json.optBoolean("repeat", true),
                        cycles = json.optInt(
                            "cycles",
                            json.optInt("rounds", 0),
                        ).coerceAtLeast(0),
                        phases = phases,
                    )
                } catch (_: Exception) {
                    null
                }
            }
        }
    }

    private data class HapticPhase(
        val label: String,
        val durationMs: Int,
        val vibrateMs: Int,
        val amplitude: Int,
    ) {
        companion object {
            fun fromJson(json: JSONObject): HapticPhase {
                return HapticPhase(
                    label = json.optString("label").ifBlank { "phase" },
                    durationMs = json.optInt("durationMs", 0),
                    vibrateMs = json.optInt("vibrateMs", 45),
                    amplitude = json.optInt("amplitude", DEFAULT_HAPTIC_AMPLITUDE),
                )
            }
        }
    }

    companion object {
        const val ACTION_START = "com.huxizen.huxi_zen.background_audio.START"
        const val ACTION_SYNC = "com.huxizen.huxi_zen.background_audio.SYNC"
        const val ACTION_STOP = "com.huxizen.huxi_zen.background_audio.STOP"
        const val ACTION_HAPTICS_START =
            "com.huxizen.huxi_zen.background_audio.HAPTICS_START"
        const val ACTION_HAPTICS_STOP =
            "com.huxizen.huxi_zen.background_audio.HAPTICS_STOP"
        private const val EXTRA_TRACKS_JSON = "tracksJson"
        private const val EXTRA_HAPTIC_PATTERN_JSON = "hapticPatternJson"
        private const val LOOP_FADE_MS = 6000
        private const val SWITCH_FADE_MS = 900
        private const val FADE_TICK_MS = 60
        private const val DEFAULT_HAPTIC_AMPLITUDE = 96

        private val statusLock = Any()
        private var lastStatus: Map<String, Any?> = mapOf(
            "running" to false,
            "trackCount" to 0,
            "lastCommand" to "idle",
            "primaryUri" to "",
            "playbackState" to "idle",
            "lastError" to "",
            "activeChannelIds" to emptyList<String>(),
            "hapticsRunning" to false,
            "hapticPatternId" to "",
            "hapticPhase" to "",
            "hapticPhaseIndex" to -1,
        )

        fun startIntent(context: Context, tracksJson: String): Intent {
            return Intent(context, BackgroundAudioService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TRACKS_JSON, tracksJson)
            }
        }

        fun syncIntent(context: Context, tracksJson: String): Intent {
            return Intent(context, BackgroundAudioService::class.java).apply {
                action = ACTION_SYNC
                putExtra(EXTRA_TRACKS_JSON, tracksJson)
            }
        }

        fun startHapticsIntent(context: Context, patternJson: String): Intent {
            return Intent(context, BackgroundAudioService::class.java).apply {
                action = ACTION_HAPTICS_START
                putExtra(EXTRA_HAPTIC_PATTERN_JSON, patternJson)
            }
        }

        fun stopHapticsIntent(context: Context): Intent {
            return Intent(context, BackgroundAudioService::class.java).apply {
                action = ACTION_HAPTICS_STOP
            }
        }

        fun status(): Map<String, Any?> = synchronized(statusLock) {
            lastStatus.toMap()
        }

        private fun updateStatus(
            running: Boolean,
            trackCount: Int,
            lastCommand: String,
            primaryUri: String = "",
            playbackState: String = "",
            lastError: String = "",
            activeChannelIds: List<String> = emptyList(),
            hapticsRunning: Boolean? = null,
            hapticPatternId: String? = null,
            hapticPhase: String? = null,
            hapticPhaseIndex: Int? = null,
        ) {
            synchronized(statusLock) {
                val previous = lastStatus
                lastStatus = mapOf(
                    "running" to running,
                    "trackCount" to trackCount,
                    "lastCommand" to lastCommand,
                    "primaryUri" to primaryUri,
                    "playbackState" to playbackState,
                    "lastError" to lastError,
                    "activeChannelIds" to activeChannelIds,
                    "hapticsRunning" to (
                        hapticsRunning ?: previous["hapticsRunning"] ?: false
                    ),
                    "hapticPatternId" to (
                        hapticPatternId ?: previous["hapticPatternId"] ?: ""
                    ),
                    "hapticPhase" to (
                        hapticPhase ?: previous["hapticPhase"] ?: ""
                    ),
                    "hapticPhaseIndex" to (
                        hapticPhaseIndex ?: previous["hapticPhaseIndex"] ?: -1
                    ),
                )
            }
        }
    }
}
