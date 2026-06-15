package dev.aetherfin.aetherfin.widget

import androidx.compose.runtime.Composable
import androidx.glance.GlanceTheme

/**
 * Aetherfin widget theme wrapper around GlanceTheme.
 *
 * Provides a consistent dark color scheme matching the app's Nocturne dark theme.
 * Will be extended with custom color providers once the design token bridge is built.
 */
@Composable
fun AetherfinWidgetTheme(content: @Composable () -> Unit) {
    GlanceTheme(content = content)
}
