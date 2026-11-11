package com.shellx.app.testing

import androidx.compose.ui.autofill.ContentType

/**
 * The Android autofill hints a [ContentType] stands for ("username", "smsOTPCode", …). Compose UI 1.11 keeps its own
 * accessor (`ContentType.contentHints`) internal, so a test reads it by reflection; a rename in a later Compose fails
 * the test by name.
 */
fun autofillHints(type: ContentType): Set<String> {
    val accessor = Class.forName("androidx.compose.ui.autofill.ContentType_androidKt").getMethod("getContentHints", ContentType::class.java)
    @Suppress("UNCHECKED_CAST")
    return (accessor.invoke(null, type) as Array<String>).toSet()
}
