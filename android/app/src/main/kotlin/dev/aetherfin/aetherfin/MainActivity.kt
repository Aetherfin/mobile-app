package dev.aetherfin.aetherfin

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.webkit.CookieManager
import androidx.core.content.ContextCompat
import dev.aetherfin.aetherfin.battery.BatteryOptPlugin
import dev.aetherfin.aetherfin.saf.SafPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Build
import android.os.Bundle
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat

class MainActivity : FlutterActivity() {
    companion object {
        var mediaSessionChannel: MethodChannel? = null
    }

    private var pendingShortcutAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        LauncherIconController.tryFixLauncherIconIfNeeded(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(BatteryOptPlugin())
        flutterEngine.plugins.add(SafPlugin())

        // YouTube auth — read cookies from android.webkit.CookieManager.
        // Server-side URL allowlist prevents exfiltrating cookies for arbitrary domains.
        val ytAllowedHosts = setOf(
            "music.youtube.com",
            "www.youtube.com",
            "accounts.google.com",
        )
        val ytAuthChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aetherfin.youtube_auth")
        ytAuthChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getCookies" -> {
                    val url = call.argument<String>("url") ?: "https://music.youtube.com"
                    val host = try { java.net.URI(url).host } catch (_: Exception) { null }
                    if (host == null || !ytAllowedHosts.contains(host)) {
                        result.error("INVALID_URL", "Cookies may only be read for allowed YouTube/Google hosts.", null)
                        return@setMethodCallHandler
                    }
                    val cookieStr = CookieManager.getInstance().getCookie(url) ?: ""
                    result.success(cookieStr)
                }
                "clearCookies" -> {
                    CookieManager.getInstance().removeAllCookies(null)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        intent?.getStringExtra("shortcut_action")?.let {
            pendingShortcutAction = it
        }
        setupShortcuts()

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aetherfin.media_session")
        mediaSessionChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "changeAppIcon" -> {
                    val icon = call.argument<String>("icon") ?: "DefaultIcon"
                    val validIcons = setOf("DefaultIcon", "MidnightIcon", "NordicIcon", "SunsetIcon")
                    if (icon !in validIcons) {
                        result.error("INVALID_ICON", "Unknown icon: $icon", null)
                        return@setMethodCallHandler
                    }
                    LauncherIconController.setIcon(this, icon)
                    result.success(null)
                }
                "updateState" -> {
                    val intent = Intent(this, AetherfinMediaSessionService::class.java).apply {
                        action = AetherfinMediaSessionService.ACTION_UPDATE_STATE
                        putExtra("playing", call.argument<Boolean>("playing") ?: false)
                        putExtra("buffering", call.argument<Boolean>("buffering") ?: false)
                        putExtra("positionMs", call.argument<Number>("positionMs")?.toLong() ?: 0L)
                        putExtra("durationMs", call.argument<Number>("durationMs")?.toLong() ?: 0L)
                        putExtra("speed", call.argument<Number>("speed")?.toDouble() ?: 1.0)
                        putExtra("title", call.argument<String>("title") ?: "")
                        putExtra("artist", call.argument<String>("artist") ?: "")
                        putExtra("album", call.argument<String>("album") ?: "")
                        putExtra("artPath", call.argument<String>("artPath"))
                        putExtra("queueIndex", call.argument<Int>("queueIndex"))
                        putExtra("queueSize", call.argument<Int>("queueSize") ?: 0)
                        putExtra("shuffleEnabled", call.argument<Boolean>("shuffleEnabled") ?: false)
                        putExtra("loopMode", call.argument<String>("loopMode") ?: "off")
                        putExtra("isFavorite", call.argument<Boolean>("isFavorite") ?: false)
                    }
                    val playing = call.argument<Boolean>("playing") ?: false
                    if (playing) {
                        ContextCompat.startForegroundService(this, intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "clear" -> {
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.cancel(AetherfinMediaSessionService.NOTIFICATION_ID)
                    val intent = Intent(this, AetherfinMediaSessionService::class.java)
                    stopService(intent)
                    result.success(null)
                }
                "getShortcutAction" -> {
                    result.success(pendingShortcutAction)
                    pendingShortcutAction = null
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.getStringExtra("shortcut_action")?.let { action ->
            mediaSessionChannel?.invokeMethod("shortcutAction", action)
        }
    }

    private fun setupShortcuts() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
            val playFavoritesShortcut = ShortcutInfoCompat.Builder(this, "play_favorites")
                .setShortLabel("Play Favorites")
                .setLongLabel("Play Favorites Playlist")
                .setIcon(IconCompat.createWithResource(this, android.R.drawable.btn_star_big_on))
                .setIntent(Intent(this, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    putExtra("shortcut_action", "play_favorites")
                })
                .build()

            val searchShortcut = ShortcutInfoCompat.Builder(this, "search_music")
                .setShortLabel("Search")
                .setLongLabel("Search Library")
                .setIcon(IconCompat.createWithResource(this, android.R.drawable.ic_menu_search))
                .setIntent(Intent(this, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    putExtra("shortcut_action", "search_music")
                })
                .build()

            ShortcutManagerCompat.addDynamicShortcuts(this, listOf(playFavoritesShortcut, searchShortcut))
        }
    }

    override fun onDestroy() {
        mediaSessionChannel?.setMethodCallHandler(null)
        // Keep mediaSessionChannel reference alive across Activity recreation
        // so AetherfinMediaSessionService commands are not silently dropped.
        // The reference is overwritten on the next configureFlutterEngine call.
        super.onDestroy()
    }
}
