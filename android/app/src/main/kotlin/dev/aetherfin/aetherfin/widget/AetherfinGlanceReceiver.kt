package dev.aetherfin.aetherfin.widget

import android.content.Context
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver

/**
 * Entry point for the Glance home-screen widget.
 *
 * Android requires an [android.appwidget.AppWidgetProvider]-derived class
 * registered in the manifest. [GlanceAppWidgetReceiver] bridges that
 * requirement to [AetherfinGlanceWidget].
 */
class AetherfinGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = AetherfinGlanceWidget()
}
