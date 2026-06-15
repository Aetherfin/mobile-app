package dev.aetherfin.aetherfin

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.session.MediaButtonReceiver
import android.content.BroadcastReceiver
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import java.io.File

class AetherfinMediaSessionService : Service() {

    companion object {
        const val ACTION_UPDATE_STATE = "dev.aetherfin.aetherfin.UPDATE_STATE"
        const val ACTION_TOGGLE_SHUFFLE = "dev.aetherfin.aetherfin.TOGGLE_SHUFFLE"
        const val ACTION_TOGGLE_REPEAT = "dev.aetherfin.aetherfin.TOGGLE_REPEAT"
        const val ACTION_TOGGLE_FAVORITE = "dev.aetherfin.aetherfin.TOGGLE_FAVORITE"
        const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "dev.aetherfin.audio"

        @JvmStatic
        var isServicePlaying = false

        @JvmStatic
        var lastDisconnectionTimeMs: Long = 0L
    }

    private var mediaSession: MediaSessionCompat? = null

    private lateinit var audioManager: AudioManager
    private var focusRequest: AudioFocusRequest? = null
    private var hasAudioFocus = false
    private var isReceiverRegistered = false

    // Playing state tracking for focus handling
    private var isCurrentlyPlaying = false
    private var wasPlayingBeforeFocusLoss = false

    private val afChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                wasPlayingBeforeFocusLoss = false
                sendCommandToFlutter("pause")
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                wasPlayingBeforeFocusLoss = isCurrentlyPlaying
                sendCommandToFlutter("pause")
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                wasPlayingBeforeFocusLoss = isCurrentlyPlaying
                sendCommandToFlutter("duck", mapOf("volume" to 0.2))
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                sendCommandToFlutter("unduck")
                if (wasPlayingBeforeFocusLoss) {
                    sendCommandToFlutter("play")
                    wasPlayingBeforeFocusLoss = false
                }
            }
        }
    }

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (AudioManager.ACTION_AUDIO_BECOMING_NOISY == intent.action) {
                lastDisconnectionTimeMs = System.currentTimeMillis()
                sendCommandToFlutter("pause")
            }
        }
    }

    private val mediaSessionCallback = object : MediaSessionCompat.Callback() {
        override fun onPlay() {
            sendCommandToFlutter("play")
        }

        override fun onPause() {
            sendCommandToFlutter("pause")
        }

        override fun onSkipToNext() {
            sendCommandToFlutter("next")
        }

        override fun onSkipToPrevious() {
            sendCommandToFlutter("previous")
        }

        override fun onStop() {
            sendCommandToFlutter("stop")
            stopSelf()
        }

        override fun onSeekTo(pos: Long) {
            sendCommandToFlutter("seek", mapOf("positionMs" to pos))
        }

        override fun onSkipToQueueItem(id: Long) {
            sendCommandToFlutter("skipTo", mapOf("queueIndex" to id.toInt()))
        }

        override fun onSetShuffleMode(shuffleMode: Int) {
            sendCommandToFlutter("setShuffleMode", mapOf("shuffleMode" to shuffleMode))
        }

        override fun onSetRepeatMode(repeatMode: Int) {
            sendCommandToFlutter("setRepeatMode", mapOf("repeatMode" to repeatMode))
        }

        override fun onCustomAction(action: String?, extras: android.os.Bundle?) {
            when (action) {
                "ACTION_SHUFFLE" -> sendCommandToFlutter("toggleShuffle")
                "ACTION_REPEAT" -> sendCommandToFlutter("toggleRepeat")
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        
        mediaSession = MediaSessionCompat(this, "AetherfinMediaSession").apply {
            setCallback(mediaSessionCallback)
            setFlags(MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS)
            isActive = true
            
            // Set session activity intent
            val intent = Intent(this@AetherfinMediaSessionService, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                this@AetherfinMediaSessionService,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            setSessionActivity(pendingIntent)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent != null) {
            when (intent.action) {
                ACTION_TOGGLE_SHUFFLE -> {
                    sendCommandToFlutter("toggleShuffle")
                    return START_NOT_STICKY
                }
                ACTION_TOGGLE_REPEAT -> {
                    sendCommandToFlutter("toggleRepeat")
                    return START_NOT_STICKY
                }
                ACTION_TOGGLE_FAVORITE -> {
                    sendCommandToFlutter("toggleFavorite")
                    return START_NOT_STICKY
                }
            }
        }

        if (intent != null && intent.action == ACTION_UPDATE_STATE) {
            val playing = intent.getBooleanExtra("playing", false)
            isCurrentlyPlaying = playing
            isServicePlaying = playing
            val buffering = intent.getBooleanExtra("buffering", false)
            val positionMs = intent.getLongExtra("positionMs", 0L)
            val durationMs = intent.getLongExtra("durationMs", 0L)
            val speed = intent.getDoubleExtra("speed", 1.0)
            val title = intent.getStringExtra("title") ?: ""
            val artist = intent.getStringExtra("artist") ?: ""
            val album = intent.getStringExtra("album") ?: ""
            val artPath = intent.getStringExtra("artPath")
            val queueIndex = if (intent.hasExtra("queueIndex")) intent.getIntExtra("queueIndex", -1) else -1
            val queueSize = intent.getIntExtra("queueSize", 0)
            val shuffleEnabled = intent.getBooleanExtra("shuffleEnabled", false)
            val loopMode = intent.getStringExtra("loopMode") ?: "off"
            val isFavorite = intent.getBooleanExtra("isFavorite", false)

            updateMediaSessionState(playing, buffering, positionMs, durationMs, speed, queueIndex, queueSize, shuffleEnabled, loopMode)
            updateMediaSessionMetadata(title, artist, album, durationMs, artPath, queueIndex)

            val widgetManager = android.appwidget.AppWidgetManager.getInstance(this)
            val widgetComponent = android.content.ComponentName(this, dev.aetherfin.aetherfin.widget.AetherfinGlanceReceiver::class.java)
            val widgetIds = widgetManager.getAppWidgetIds(widgetComponent)
            if (widgetIds.isNotEmpty()) {
                val updateIntent = Intent(this, dev.aetherfin.aetherfin.widget.AetherfinGlanceReceiver::class.java).apply {
                    action = android.appwidget.AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(android.appwidget.AppWidgetManager.EXTRA_APPWIDGET_IDS, widgetIds)
                }
                sendBroadcast(updateIntent)
            }

            val notification = buildNotification(
                title, artist, album, playing, artPath,
                hasPrev = queueIndex > 0,
                hasNext = queueIndex < queueSize - 1 && queueIndex >= 0,
                shuffleEnabled = shuffleEnabled,
                loopMode = loopMode
            )
            
            if (playing) {
                if (requestAudioFocus()) {
                    registerNoisyReceiver()
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
            } else {
                unregisterNoisyReceiver()
                abandonAudioFocus()
                // When paused: demote from foreground so the user can swipe the
                // notification away, but keep the notification visible so they
                // can resume from QS/lock-screen.
                //
                // Android 12+ (S, API 31) deprecated the boolean overload of
                // stopForeground(). Use STOP_FOREGROUND_DETACH to keep the
                // notification posted (equivalent to stopForeground(false))
                // without the deprecation warning.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    stopForeground(STOP_FOREGROUND_DETACH)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(false)
                }
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.notify(NOTIFICATION_ID, notification)
            }
        }
        
        // Handle media buttons via receiver
        MediaButtonReceiver.handleIntent(mediaSession, intent)
        return START_NOT_STICKY
    }

    private fun requestAudioFocus(): Boolean {
        if (hasAudioFocus) return true

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val playbackAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            
            focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(playbackAttributes)
                .setAcceptsDelayedFocusGain(true)
                .setOnAudioFocusChangeListener(afChangeListener)
                .build()

            val res = audioManager.requestAudioFocus(focusRequest!!)
            hasAudioFocus = res == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            hasAudioFocus
        } else {
            @Suppress("DEPRECATION")
            val res = audioManager.requestAudioFocus(
                afChangeListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN
            )
            hasAudioFocus = res == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            hasAudioFocus
        }
    }

    private fun abandonAudioFocus() {
        if (!hasAudioFocus) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(afChangeListener)
        }
        hasAudioFocus = false
    }

    private fun registerNoisyReceiver() {
        if (isReceiverRegistered) return
        registerReceiver(noisyReceiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
        isReceiverRegistered = true
    }

    private fun unregisterNoisyReceiver() {
        if (!isReceiverRegistered) return
        try {
            unregisterReceiver(noisyReceiver)
        } catch (e: Exception) {
            // Ignore
        }
        isReceiverRegistered = false
    }

    private fun updateMediaSessionState(
        playing: Boolean,
        buffering: Boolean,
        positionMs: Long,
        durationMs: Long,
        speed: Double,
        queueIndex: Int,
        queueSize: Int,
        shuffleEnabled: Boolean = false,
        loopMode: String = "off"
    ) {
        val state = when {
            buffering -> PlaybackStateCompat.STATE_BUFFERING
            playing -> PlaybackStateCompat.STATE_PLAYING
            else -> PlaybackStateCompat.STATE_PAUSED
        }

        // When paused/stopped, only advertise ACTION_PLAY (not ACTION_PAUSE).
        // Advertising ACTION_PAUSE while in STATE_PAUSED causes some OEM skins
        // (Samsung One UI, MIUI) to show a "pause" button even though nothing
        // is playing, which is exactly the wrong UI.
        var actions = if (playing) {
            PlaybackStateCompat.ACTION_PLAY_PAUSE or
                    PlaybackStateCompat.ACTION_PAUSE or
                    PlaybackStateCompat.ACTION_SEEK_TO
        } else {
            PlaybackStateCompat.ACTION_PLAY_PAUSE or
                    PlaybackStateCompat.ACTION_PLAY
        }

        // Always advertise prev/next so the QS layout stays stable.
        // Tapping them while at bounds is handled gracefully on the Dart side.
        actions = actions or PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
        actions = actions or PlaybackStateCompat.ACTION_SKIP_TO_NEXT

        // Use speed=0f when not playing. Passing the real playback speed
        // (e.g. 1.0f) alongside STATE_PAUSED causes some Android/OEM
        // framework versions to continue extrapolating the position forward,
        // which is the root cause of the QS progress bar running after
        // the queue ends.
        val effectiveSpeed = if (playing) speed.toFloat() else 0f

        // Use ACTION_SET_SHUFFLE_MODE / ACTION_SET_REPEAT_MODE in the actions
        // bitmask so Android renders the standard shuffle/repeat buttons in the
        // notification and QS. When pressed, they route to onSetShuffleMode() /
        // onSetRepeatMode() on the MediaSession callback below.
        //
        // Note: PlaybackStateCompat.Builder in androidx.media:media does not
        // expose setShuffleMode()/setRepeatMode() builder methods, so the
        // current toggle icon state is not encoded in PlaybackState. The
        // notification buttons still work — they send the command to Flutter
        // via MethodChannel, and the Dart side toggles the mode.
        val stateBuilder = PlaybackStateCompat.Builder()
            .setActions(actions)
            .setState(state, positionMs, effectiveSpeed, SystemClock.elapsedRealtime())

        if (queueIndex >= 0) {
            stateBuilder.setActiveQueueItemId(queueIndex.toLong())
        }

        val androidShuffleMode = if (shuffleEnabled) {
            PlaybackStateCompat.SHUFFLE_MODE_ALL
        } else {
            PlaybackStateCompat.SHUFFLE_MODE_NONE
        }
        mediaSession?.setShuffleMode(androidShuffleMode)

        val androidRepeatMode = when (loopMode) {
            "one" -> PlaybackStateCompat.REPEAT_MODE_ONE
            "all", "ntimes" -> PlaybackStateCompat.REPEAT_MODE_ALL
            else -> PlaybackStateCompat.REPEAT_MODE_NONE
        }
        mediaSession?.setRepeatMode(androidRepeatMode)

        val shuffleIcon = if (shuffleEnabled) {
            R.drawable.ic_shuffle_on
        } else {
            R.drawable.ic_shuffle_off
        }
        val shuffleLabel = if (shuffleEnabled) "Shuffle On" else "Shuffle Off"
        val shuffleAction = PlaybackStateCompat.CustomAction.Builder(
            "ACTION_SHUFFLE",
            shuffleLabel,
            shuffleIcon
        ).build()
        stateBuilder.addCustomAction(shuffleAction)

        val repeatIcon = when (loopMode) {
            "one" -> R.drawable.ic_repeat_one
            "all" -> R.drawable.ic_repeat_all
            "ntimes" -> R.drawable.ic_repeat_ntimes
            else -> R.drawable.ic_repeat_off
        }
        val repeatLabel = when (loopMode) {
            "one" -> "Repeat One"
            "all" -> "Repeat All"
            "ntimes" -> "Repeat 2"
            else -> "Repeat Off"
        }
        val repeatAction = PlaybackStateCompat.CustomAction.Builder(
            "ACTION_REPEAT",
            repeatLabel,
            repeatIcon
        ).build()
        stateBuilder.addCustomAction(repeatAction)

        mediaSession?.setPlaybackState(stateBuilder.build())
    }

    private fun updateMediaSessionMetadata(
        title: String,
        artist: String,
        album: String,
        durationMs: Long,
        artPath: String?,
        queueIndex: Int
    ) {
        val metadataBuilder = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)

        if (queueIndex >= 0) {
            metadataBuilder.putLong(MediaMetadataCompat.METADATA_KEY_TRACK_NUMBER, queueIndex.toLong() + 1)
        }

        if (!artPath.isNullOrEmpty()) {
            val bitmap = loadScaledBitmap(artPath, 1024)
            if (bitmap != null) {
                metadataBuilder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, bitmap)
            }
        }

        mediaSession?.setMetadata(metadataBuilder.build())
    }

    private fun buildNotification(
        title: String,
        artist: String,
        album: String,
        playing: Boolean,
        artPath: String?,
        hasPrev: Boolean,
        hasNext: Boolean,
        shuffleEnabled: Boolean = false,
        loopMode: String = "off"
    ): Notification {
        createNotificationChannel()

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(artist)
            .setSubText(album)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(playing)
            .setShowWhen(false)

        if (!artPath.isNullOrEmpty()) {
            val bitmap = loadScaledBitmap(artPath, 1024)
            if (bitmap != null) {
                builder.setLargeIcon(bitmap)
            }
        }

        // Action when content is clicked
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        builder.setContentIntent(pendingIntent)

        // 1. Previous Action
        val prevIntent = if (hasPrev) {
            MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS)
        } else {
            null
        }
        builder.addAction(android.R.drawable.ic_media_previous, "Previous", prevIntent)

        // 3. Play/Pause Action
        val playPauseAction = if (playing) {
            NotificationCompat.Action(
                android.R.drawable.ic_media_pause,
                "Pause",
                MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_PAUSE)
            )
        } else {
            NotificationCompat.Action(
                android.R.drawable.ic_media_play,
                "Play",
                MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_PLAY)
            )
        }
        builder.addAction(playPauseAction)

        // 4. Next Action
        val nextIntent = if (hasNext) {
            MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_SKIP_TO_NEXT)
        } else {
            null
        }
        builder.addAction(android.R.drawable.ic_media_next, "Next", nextIntent)

        // 5. Shuffle Action
        val shuffleIcon = if (shuffleEnabled) R.drawable.ic_shuffle_on else R.drawable.ic_shuffle_off
        val shuffleLabel = if (shuffleEnabled) "Shuffle On" else "Shuffle Off"
        val shuffleIntent = PendingIntent.getService(
            this,
            0,
            Intent(this, AetherfinMediaSessionService::class.java).apply {
                action = ACTION_TOGGLE_SHUFFLE
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        builder.addAction(NotificationCompat.Action(shuffleIcon, shuffleLabel, shuffleIntent))

        // 6. Repeat Action
        val repeatIcon = when (loopMode) {
            "one" -> R.drawable.ic_repeat_one
            "all" -> R.drawable.ic_repeat_all
            "ntimes" -> R.drawable.ic_repeat_ntimes
            else -> R.drawable.ic_repeat_off
        }
        val repeatLabel = when (loopMode) {
            "one" -> "Repeat One"
            "all" -> "Repeat All"
            "ntimes" -> "Repeat 2"
            else -> "Repeat Off"
        }
        val repeatIntent = PendingIntent.getService(
            this,
            0,
            Intent(this, AetherfinMediaSessionService::class.java).apply {
                action = ACTION_TOGGLE_REPEAT
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        builder.addAction(NotificationCompat.Action(repeatIcon, repeatLabel, repeatIntent))

        val style = androidx.media.app.NotificationCompat.MediaStyle()
            .setMediaSession(mediaSession?.sessionToken)
            .setShowActionsInCompactView(0, 1, 2)

        builder.setStyle(style)
        return builder.build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Aetherfin playback"
            val descriptionText = "Playback notification controls"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
                setShowBadge(false)
                setSound(null, null)
                enableLights(false)
                enableVibration(false)
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun sendCommandToFlutter(method: String, args: Any? = null) {
        MainActivity.mediaSessionChannel?.let { channel ->
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                try {
                    channel.invokeMethod(method, args)
                } catch (e: Exception) {
                    // Stale channel during Activity recreation — safe to ignore.
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        sendCommandToFlutter("stop")
        stopSelf()
    }

    private fun loadScaledBitmap(filePath: String, maxDim: Int): Bitmap? {
        try {
            val file = File(filePath)
            if (!file.exists()) return null

            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeFile(file.absolutePath, options)

            var inSampleSize = 1
            if (options.outHeight > maxDim || options.outWidth > maxDim) {
                val halfHeight = options.outHeight / 2
                val halfWidth = options.outWidth / 2
                while (halfHeight / inSampleSize >= maxDim && halfWidth / inSampleSize >= maxDim) {
                    inSampleSize *= 2
                }
            }

            options.inJustDecodeBounds = false
            options.inSampleSize = inSampleSize
            val decoded = BitmapFactory.decodeFile(file.absolutePath, options) ?: return null

            if (decoded.width > maxDim || decoded.height > maxDim) {
                val width: Int
                val height: Int
                if (decoded.width > decoded.height) {
                    width = maxDim
                    height = (decoded.height * (maxDim.toDouble() / decoded.width)).toInt()
                } else {
                    height = maxDim
                    width = (decoded.width * (maxDim.toDouble() / decoded.height)).toInt()
                }
                val scaled = Bitmap.createScaledBitmap(decoded, width, height, true)
                if (scaled != decoded) {
                    decoded.recycle()
                }
                return scaled
            }
            return decoded
        } catch (e: Exception) {
            return null
        }
    }

    override fun onDestroy() {
        isServicePlaying = false
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(NOTIFICATION_ID)
        abandonAudioFocus()
        unregisterNoisyReceiver()
        mediaSession?.apply {
            // Explicitly set STATE_STOPPED before releasing. Without this,
            // Android MediaSession retains the last STATE_PLAYING anchor
            // (with its elapsedRealtime timestamp) and QS Media continues to
            // extrapolate the progress bar forward even after the service
            // is destroyed.
            val stoppedState = PlaybackStateCompat.Builder()
                .setState(
                    PlaybackStateCompat.STATE_STOPPED,
                    0L,
                    0f,
                    SystemClock.elapsedRealtime()
                )
                .setActions(0)
                .build()
            setPlaybackState(stoppedState)
            isActive = false
            release()
        }
        mediaSession = null
        super.onDestroy()
    }
}
