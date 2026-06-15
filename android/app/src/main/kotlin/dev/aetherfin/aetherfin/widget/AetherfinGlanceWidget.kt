package dev.aetherfin.aetherfin.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.glance.GlanceId
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.provideContent
import dev.aetherfin.aetherfin.widget.layouts.CompactLayout

/**
 * Glance-based home screen widget for Aetherfin.
 *
 * Reads playback state from Flutter's SharedPreferences (flutter.title, flutter.artist, etc.)
 * and renders a compact now-playing card with artwork, metadata, and transport controls.
 *
 * Three layout sizes are supported: Compact (4x1), Standard (4x2), Spotlight (4x3).
 * The layout is selected via [sizeMode] configuration.
 */
class AetherfinGlanceWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE,
        )

        // Flutter stores these as String values, not native booleans
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
                )
            }
        }
    }
}
