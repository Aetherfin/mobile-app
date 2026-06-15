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
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider

/**
 * Standard 4×2 widget layout — larger artwork, full metadata row, and transport controls.
 *
 * Layout: [artwork (left) | Column of [title, artist, row of controls] (right)].
 * Two rows of height give room for title + artist + transport.
 */
@Composable
fun StandardLayout(
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
            .padding(12.dp)
            .cornerRadius(16.dp)
            .background(bgColor),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Artwork placeholder
        Box(
            modifier = GlanceModifier
                .size(80.dp)
                .cornerRadius(8.dp)
                .background(surfaceColor),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "\u266A",
                style = TextStyle(
                    color = textMuted,
                    fontSize = 32.sp,
                ),
            )
        }

        Column(
            modifier = GlanceModifier
                .defaultWeight()
                .padding(horizontal = 12.dp),
        ) {
            // Title
            Text(
                text = title,
                maxLines = 1,
                style = TextStyle(
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Medium,
                    color = textPrimary,
                ),
            )

            // Artist
            Text(
                text = artist,
                maxLines = 1,
                style = TextStyle(
                    fontSize = 13.sp,
                    color = textSecondary,
                ),
            )

            // Spacer
            Box(modifier = GlanceModifier.height(4.dp)) {}

            // Transport row — placeholder text buttons
            Row(
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "\u23EE",
                    modifier = GlanceModifier.padding(horizontal = 4.dp),
                    style = TextStyle(
                        fontSize = 16.sp,
                        color = textPrimary,
                    ),
                )

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
                        fontSize = 16.sp,
                        color = textPrimary,
                    ),
                )

                // Spacer pushes favorite to end
                Box(modifier = GlanceModifier.defaultWeight()) {}

                Text(
                    text = if (isFavorite) "\u2665" else "\u2661",
                    modifier = GlanceModifier.padding(horizontal = 4.dp),
                    style = TextStyle(
                        fontSize = 16.sp,
                        color = textPrimary,
                    ),
                )
            }
        }
    }
}
