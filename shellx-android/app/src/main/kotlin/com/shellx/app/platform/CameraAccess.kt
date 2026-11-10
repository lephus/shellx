package com.shellx.app.platform

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat

/** Whether the QR scanner can use the camera (`CameraAccess.swift`). */
enum class CameraAccess {
    /** Not asked yet: the pairing page asks when the scanner is about to show. */
    NOT_DETERMINED,
    AUTHORIZED,

    /** The user refused the request (or turned it off in Settings). */
    DENIED,

    /** No camera at all. */
    UNAVAILABLE,
    ;

    companion object {
        /** No camera (FEATURE_CAMERA_ANY) → UNAVAILABLE; CAMERA granted → AUTHORIZED; else NOT_DETERMINED (DENIED comes
         *  only from a refused request). */
        fun current(context: Context): CameraAccess = when {
            !context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY) -> UNAVAILABLE
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED ->
                AUTHORIZED
            else -> NOT_DETERMINED
        }
    }
}
