package com.shellx.app.voice

import android.content.Context
import android.content.Intent
import android.os.Build
import android.speech.RecognitionListener
import android.speech.SpeechRecognizer
import com.shellx.core.platform.CoreLog

/** Which platform recognizer a [SpeechRecognizerEngine] runs (S3 §7.3). */
enum class RecognizerKind {
    /** `SpeechRecognizer.createOnDeviceSpeechRecognizer` (API 31 and later). */
    ON_DEVICE,

    /** `SpeechRecognizer.createSpeechRecognizer`: the phone's speech service. */
    STANDARD,
}

/** One platform recognizer for one run. [SystemRecognizerPort] wraps `android.speech.SpeechRecognizer`; every call is
 *  made on the main thread. */
interface RecognizerPort {
    /** Sets [listener], then starts listening with [intent]. */
    fun start(intent: Intent, listener: RecognitionListener)

    /** Stops listening: the recognizer delivers its final result. */
    fun stop()

    fun cancel()

    fun destroy()
}

class SystemRecognizerPort(private val recognizer: SpeechRecognizer) : RecognizerPort {
    override fun start(intent: Intent, listener: RecognitionListener) {
        recognizer.setRecognitionListener(listener)
        recognizer.startListening(intent)
    }

    override fun stop() = recognizer.stopListening()

    override fun cancel() = recognizer.cancel()

    override fun destroy() = recognizer.destroy()

    companion object {
        /**
         * ON_DEVICE: API 31+ and `SpeechRecognizer.isOnDeviceRecognitionAvailable` → `createOnDeviceSpeechRecognizer`.
         * STANDARD: `SpeechRecognizer.isRecognitionAvailable` → `createSpeechRecognizer`. Otherwise (or when the phone
         * refuses to make one) null. Main thread.
         */
        fun create(context: Context, kind: RecognizerKind): RecognizerPort? = try {
            when (kind) {
                RecognizerKind.ON_DEVICE ->
                    if (Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
                        SystemRecognizerPort(SpeechRecognizer.createOnDeviceSpeechRecognizer(context))
                    } else {
                        null
                    }
                RecognizerKind.STANDARD ->
                    if (SpeechRecognizer.isRecognitionAvailable(context)) {
                        SystemRecognizerPort(SpeechRecognizer.createSpeechRecognizer(context))
                    } else {
                        null
                    }
            }
        } catch (e: RuntimeException) {
            CoreLog.log("speech_recognizer_create_failed ${e.javaClass.simpleName}")
            null
        }
    }
}
