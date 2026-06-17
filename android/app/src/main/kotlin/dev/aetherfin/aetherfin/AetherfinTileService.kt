package dev.aetherfin.aetherfin

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class AetherfinTileService : TileService() {

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            updateTile()
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                receiver,
                IntentFilter(AetherfinMediaSessionService.ACTION_UPDATE_STATE),
                Context.RECEIVER_NOT_EXPORTED
            )
        } else {
            registerReceiver(
                receiver,
                IntentFilter(AetherfinMediaSessionService.ACTION_UPDATE_STATE)
            )
        }
        updateTile()
    }

    override fun onStopListening() {
        try {
            unregisterReceiver(receiver)
        } catch (e: Exception) {
            // Ignore
        }
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        // Toggle play/pause by sending play/pause action to the media service
        val intent = Intent(this, AetherfinMediaSessionService::class.java).apply {
            action = Intent.ACTION_MEDIA_BUTTON
            putExtra(Intent.EXTRA_KEY_EVENT, android.view.KeyEvent(
                android.view.KeyEvent.ACTION_DOWN,
                android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            ))
        }
        try {
            startService(intent)
        } catch (e: Exception) {
            // Ignore failure
        }

        // Toggle state locally immediately for snappy visual feedback
        val tile = qsTile ?: return
        if (tile.state == Tile.STATE_ACTIVE) {
            tile.state = Tile.STATE_INACTIVE
        } else {
            tile.state = Tile.STATE_ACTIVE
        }
        tile.updateTile()
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        val playing = AetherfinMediaSessionService.isServicePlaying

        if (playing) {
            tile.state = Tile.STATE_ACTIVE
            tile.label = "Aetherfin (Playing)"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                tile.subtitle = "Tap to Pause"
            }
        } else {
            tile.state = Tile.STATE_INACTIVE
            tile.label = "Aetherfin (Paused)"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                tile.subtitle = "Tap to Play"
            }
        }
        tile.updateTile()
    }
}
