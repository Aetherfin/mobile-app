package dev.aetherfin.aetherfin.widget.layouts

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider

/**
 * Compact 4×1 widget layout — artwork thumbnail, title/artist, and transport controls.
 *
 * Sits in a single row: [artwork | metadata | controls].
 * Designed for minimal home screen real estate.
 */
@Composable
fun CompactLayout(
    title: String,
    artist: String,
    isPlaying: Boolean,
    artPath: String?,
    isFavorite: Boolean,
) {
    val bgColor = Color(0xFF1A1A2E)
    val surfaceColor = Color(0xFF2A2A3E)
    val textPrimary = ColorProvider(0xFFFFFFFF.toInt())
    val textSecondary = ColorProvider(0xBBFFFFFF.toInt())
    val textMuted = ColorProvider(0xFF8888AA.toInt())

    Row(
        modifier = GlanceModifier
            .fillMaxSize()
            .padding(8.dp)
            .cornerRadius(16.dp)
            .background(bgColor),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Artwork placeholder — will load bitmap from artPath in future iteration
        Box(
            modifier = GlanceModifier
                .size(56.dp)
                .cornerRadius(8.dp)
                .background(surfaceColor),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "\u266A",
                style = TextStyle(
                    color = textMuted,
                    fontSize = 24.sp,
                ),
            )
        }

        // Metadata
        Column(
            modifier = GlanceModifier
                .defaultWeight()
                .padding(horizontal = 12.dp),
        ) {
            Text(
                text = title,
                maxLines = 1,
                style = TextStyle(
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    color = textPrimary,
                ),
            )
            Text(
                text = artist,
                maxLines = 1,
                style = TextStyle(
                    fontSize = 12.sp,
                    color = textSecondary,
                ),
            )
        }

        // Transport controls — placeholder text buttons (will be replaced with actions later)
        Text(
            text = if (isPlaying) "\u23F8" else "\u25B6",
            modifier = GlanceModifier.padding(horizontal = 4.dp),
            style = TextStyle(
                fontSize = 18.sp,
                color = textPrimary,
            ),
        )

        Text(
            text = "\u23ED",
            modifier = GlanceModifier.padding(horizontal = 4.dp),
            style = TextStyle(
                fontSize = 18.sp,
                color = textPrimary,
            ),
        )
    }
}
