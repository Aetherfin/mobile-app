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
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider

/**
 * Spotlight 4×3 widget layout — large artwork with metadata and controls overlaid.
 *
 * Layout: [full-width artwork area (top 2/3) | metadata + controls row (bottom 1/3)].
 * Designed for users who want prominent album art on their home screen.
 */
@Composable
fun SpotlightLayout(
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

    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .padding(8.dp)
            .cornerRadius(16.dp)
            .background(bgColor),
    ) {
        // Artwork area — takes up ~2/3 of widget height
        Box(
            modifier = GlanceModifier
                .fillMaxWidth()
                .height(160.dp)
                .cornerRadius(12.dp)
                .background(surfaceColor),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "\u266A",
                style = TextStyle(
                    color = textMuted,
                    fontSize = 48.sp,
                ),
            )
        }

        // Bottom section: metadata + controls
        Row(
            modifier = GlanceModifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Metadata column
            Column(
                modifier = GlanceModifier.defaultWeight(),
            ) {
                Text(
                    text = title,
                    maxLines = 1,
                    style = TextStyle(
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Medium,
                        color = textPrimary,
                    ),
                )
                Text(
                    text = artist,
                    maxLines = 1,
                    style = TextStyle(
                        fontSize = 13.sp,
                        color = textSecondary,
                    ),
                )
            }

            // Favorite
            Text(
                text = if (isFavorite) "\u2665" else "\u2661",
                modifier = GlanceModifier.padding(horizontal = 4.dp),
                style = TextStyle(
                    fontSize = 16.sp,
                    color = textPrimary,
                ),
            )

            // Previous
            Text(
                text = "\u23EE",
                modifier = GlanceModifier.padding(horizontal = 4.dp),
                style = TextStyle(
                    fontSize = 16.sp,
                    color = textPrimary,
                ),
            )

            // Play/Pause
            Text(
                text = if (isPlaying) "\u23F8" else "\u25B6",
                modifier = GlanceModifier.padding(horizontal = 4.dp),
                style = TextStyle(
                    fontSize = 18.sp,
                    color = textPrimary,
                ),
            )

            // Next
            Text(
                text = "\u23ED",
                modifier = GlanceModifier.padding(horizontal = 4.dp),
                style = TextStyle(
                    fontSize = 16.sp,
                    color = textPrimary,
                ),
            )
        }
    }
}
