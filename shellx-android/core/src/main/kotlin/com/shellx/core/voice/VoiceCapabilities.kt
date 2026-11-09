package com.shellx.core.voice

/**
 * The recognizer the mic uses for a language. Android (S3 §7.3): the on-device recognizer
 * (`SpeechRecognizer.createOnDeviceSpeechRecognizer`, API 31+) first, then the standard `SpeechRecognizer` on the
 * phone, then the standard one through the phone's speech service.
 */
enum class VoiceEngine {
    /** `createOnDeviceSpeechRecognizer` (API 31 and later). */
    ON_DEVICE_RECOGNIZER,

    /** The standard `SpeechRecognizer`, recognizing on the phone. */
    ON_DEVICE,

    /** The standard `SpeechRecognizer` through the phone's speech service; Settings says so. */
    SERVER,
}

/** What the phone can do for one spoken language right now. */
data class VoiceCapabilities(
    /** The on-device recognizer can transcribe the language on this phone now. */
    val onDeviceRecognizer: Boolean,
    /** The standard recognizer can recognise the language on this phone. */
    val standardOnDevice: Boolean,
    /** The standard recognizer is available for the language (through the speech service when not on the phone). */
    val standardAvailable: Boolean,
) {
    /** The on-device recognizer first, then the standard one on the phone, then through the speech service. Null only
     *  when no path is left: the mic is never off just because the language cannot run on the phone. */
    val engine: VoiceEngine?
        get() = when {
            onDeviceRecognizer -> VoiceEngine.ON_DEVICE_RECOGNIZER
            standardOnDevice -> VoiceEngine.ON_DEVICE
            standardAvailable -> VoiceEngine.SERVER
            else -> null
        }

    companion object {
        /** Nothing can recognise the language. */
        val NONE = VoiceCapabilities(onDeviceRecognizer = false, standardOnDevice = false, standardAvailable = false)
    }
}
