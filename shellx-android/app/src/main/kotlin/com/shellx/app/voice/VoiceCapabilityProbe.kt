package com.shellx.app.voice

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import com.shellx.core.platform.CoreLog
import com.shellx.core.voice.VoiceCapabilities
import com.shellx.core.voice.VoiceLanguage
import java.util.Collections
import kotlin.coroutines.resume
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * What can recognize a spoken language right now (`VoiceCapabilityProbe.swift`, S3 §7.3):
 * - the on-device recognizer, on API 31+, when the phone has one, the language never failed to start on it, and the
 *   phone does not say the language is missing (API 31–32 cannot tell, so it is tried; a start failure falls back
 *   through 3C's `FallbackTranscriber` and [markFailed] keeps it from being offered again);
 * - the standard recognizer, and whether it recognizes the language on the phone (API 33+, its installed languages).
 *
 * 3C's `VoiceCapabilityCache` decides how long an answer is reused.
 */
class VoiceCapabilityProbe(
    private val sdkInt: Int,
    private val onDeviceAvailable: () -> Boolean,
    private val standardAvailable: () -> Boolean,
    /** API 33+: the languages installed on the device for that recognizer (checkRecognitionSupport); null when
     *  unknown. */
    private val installedLanguages: suspend (RecognizerKind, VoiceLanguage) -> Set<String>?,
) {
    private val failed: MutableSet<VoiceLanguage> = Collections.synchronizedSet(HashSet())

    suspend fun capabilities(language: VoiceLanguage): VoiceCapabilities {
        val onDevice = sdkInt >= 31 && onDeviceAvailable() && language !in failed &&
            installedLanguages(RecognizerKind.ON_DEVICE, language).let { it == null || it.any { tag -> matches(tag, language) } }
        val standard = standardAvailable()
        val standardOnDevice = standard && sdkInt >= 33 &&
            installedLanguages(RecognizerKind.STANDARD, language)?.any { matches(it, language) } == true
        return VoiceCapabilities(onDeviceRecognizer = onDevice, standardOnDevice = standardOnDevice, standardAvailable = standard)
    }

    suspend fun onDeviceReady(language: VoiceLanguage): Boolean = capabilities(language).onDeviceRecognizer

    suspend fun standardOnDevice(language: VoiceLanguage): Boolean = capabilities(language).standardOnDevice

    /** The on-device recognizer failed to start for [language]: it is not offered again in this process. */
    fun markFailed(language: VoiceLanguage) {
        failed += language
    }

    companion object {
        /** How long the phone may take to say which languages a recognizer has. */
        val SUPPORT_TIMEOUT: Duration = 2.seconds

        /** The phone's recognizers. */
        fun system(context: Context): VoiceCapabilityProbe {
            val app = context.applicationContext
            return VoiceCapabilityProbe(
                sdkInt = Build.VERSION.SDK_INT,
                onDeviceAvailable = {
                    Build.VERSION.SDK_INT >= 31 && runCatching { SpeechRecognizer.isOnDeviceRecognitionAvailable(app) }.getOrDefault(false)
                },
                standardAvailable = { runCatching { SpeechRecognizer.isRecognitionAvailable(app) }.getOrDefault(false) },
                installedLanguages = { kind, _ ->
                    if (Build.VERSION.SDK_INT >= 33) withTimeoutOrNull(SUPPORT_TIMEOUT) { installed(app, kind) } else null
                },
            )
        }

        /** Equal ignoring case, or the same first subtag (split on `-` or `_`). */
        fun matches(tag: String, language: VoiceLanguage): Boolean {
            if (tag.equals(language.tag, ignoreCase = true)) return true
            fun first(value: String) = value.split('-', '_').firstOrNull { it.isNotEmpty() }
            val mine = first(language.tag) ?: return false
            return first(tag)?.equals(mine, ignoreCase = true) == true
        }

        /** The languages installed for [kind]'s recognizer, asked on the main thread through a fresh recognizer that is
         *  destroyed afterwards; null on an error. */
        @RequiresApi(33)
        private suspend fun installed(context: Context, kind: RecognizerKind): Set<String>? = withContext(Dispatchers.Main.immediate) {
            val recognizer = try {
                when (kind) {
                    RecognizerKind.ON_DEVICE -> SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
                    RecognizerKind.STANDARD -> SpeechRecognizer.createSpeechRecognizer(context)
                }
            } catch (e: RuntimeException) {
                CoreLog.log("speech_support_failed ${e.javaClass.simpleName}")
                return@withContext null
            }
            val main = Handler(Looper.getMainLooper())
            var destroyed = false
            fun destroy() {
                if (destroyed) return
                destroyed = true
                recognizer.destroy()
            }
            suspendCancellableCoroutine { continuation ->
                // A timeout cancels from elsewhere: the recognizer is destroyed on the main thread.
                continuation.invokeOnCancellation { main.post(::destroy) }
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                    .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                try {
                    recognizer.checkRecognitionSupport(
                        intent, ContextCompat.getMainExecutor(context),
                        object : RecognitionSupportCallback {
                            override fun onSupportResult(support: RecognitionSupport) {
                                destroy()
                                if (continuation.isActive) continuation.resume(support.installedOnDeviceLanguages.toSet())
                            }

                            override fun onError(error: Int) {
                                destroy()
                                CoreLog.log("speech_support_error code=$error")
                                if (continuation.isActive) continuation.resume(null)
                            }
                        },
                    )
                } catch (e: RuntimeException) {
                    destroy()
                    CoreLog.log("speech_support_failed ${e.javaClass.simpleName}")
                    if (continuation.isActive) continuation.resume(null)
                }
            }
        }
    }
}
