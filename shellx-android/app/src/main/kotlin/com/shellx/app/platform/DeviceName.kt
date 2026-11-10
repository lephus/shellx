package com.shellx.app.platform

import android.content.Context
import android.os.Build
import android.provider.Settings

/** The name this phone signs in with, shown in the Mac's Paired Phones (the iPhone's UIDevice.current.name). */
object DeviceName {
    /** relay/src/auth/device.ts DEVICE_NAME_MAX_CHARS: the relay counts code points after trimming. */
    const val MAX_CODE_POINTS = 100

    /** The first non-blank of [settingName] and [model], trimmed, else "Android"; cut to [MAX_CODE_POINTS] code points. */
    fun of(settingName: String?, model: String?): String {
        val name = listOfNotNull(settingName, model).map { it.trim() }.firstOrNull { it.isNotEmpty() } ?: "Android"
        if (name.codePointCount(0, name.length) <= MAX_CODE_POINTS) return name
        return name.substring(0, name.offsetByCodePoints(0, MAX_CODE_POINTS))
    }

    /** Settings › About phone › Device name (API 25+), else the model. */
    fun current(context: Context): String =
        of(Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME), Build.MODEL)
}
