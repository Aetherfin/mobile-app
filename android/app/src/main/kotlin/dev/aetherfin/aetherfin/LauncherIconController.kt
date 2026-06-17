package dev.aetherfin.aetherfin

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

object LauncherIconController {
    private val icons = listOf(
        "DefaultIcon",
        "MidnightIcon",
        "NordicIcon",
        "SunsetIcon"
    )

    fun tryFixLauncherIconIfNeeded(context: Context) {
        var anyEnabled = false
        val pm = context.packageManager
        for (iconName in icons) {
            val componentName = ComponentName(context.packageName, "${context.packageName}.$iconName")
            val state = pm.getComponentEnabledSetting(componentName)
            if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                anyEnabled = true
                break
            }
        }
        if (!anyEnabled) {
            setIcon(context, "DefaultIcon")
        }
    }

    fun setIcon(context: Context, targetIconName: String) {
        val pm = context.packageManager
        for (iconName in icons) {
            val componentName = ComponentName(context.packageName, "${context.packageName}.$iconName")
            val state = if (iconName == targetIconName) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
            pm.setComponentEnabledSetting(
                componentName,
                state,
                PackageManager.DONT_KILL_APP
            )
        }
    }
}
