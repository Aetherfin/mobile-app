package dev.aetherfin.aetherfin.widget

import android.content.Context
import android.content.Intent
import androidx.glance.GlanceId
import androidx.glance.action.actionStartActivity
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.provideContent
import dev.aetherfin.aetherfin.MainActivity
import dev.aetherfin.aetherfin.widget.layouts.CompactLayout

class AetherfinGlanceWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE,
        )

        val title = prefs.getString("flutter.title", null) ?: "Not Playing"
        val artist = prefs.getString("flutter.artist", null) ?: ""
        val isPlaying = prefs.getString("flutter.playing", "false") == "true"
        val artPath = prefs.getString("flutter.artPath", null)
        val isFavorite = prefs.getString("flutter.isFavorite", "false") == "true"

        provideContent {
            AetherfinWidgetTheme {
                CompactLayout(
                    title = title,
                    artist = artist,
                    isPlaying = isPlaying,
                    artPath = artPath,
                    isFavorite = isFavorite,
                    onTap = actionStartActivity<MainActivity>(),
                )
            }
        }
    }
}
