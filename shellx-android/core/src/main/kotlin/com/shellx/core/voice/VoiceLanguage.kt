package com.shellx.core.voice

import com.shellx.core.platform.KeyValueStore

/**
 * The language the user speaks to the mic: Vietnamese or English. By default Vietnamese when the phone's preferred
 * languages include it; the user's choice in Settings is kept in the settings store under [SETTINGS_KEY].
 */
enum class VoiceLanguage(val tag: String) {
    VIETNAMESE("vi-VN"),
    ENGLISH("en-US");

    fun save(settings: KeyValueStore) {
        settings.putString(SETTINGS_KEY, tag)
    }

    companion object {
        /** Where the user's choice is kept (the iPhone's key). */
        const val SETTINGS_KEY = "shellx.voice.language"

        /** Vietnamese when any of [preferredLanguages] (BCP 47 tags) is Vietnamese: its first part, split on `-` or
         *  `_` with empty parts skipped, is "vi" in any case. Otherwise English. */
        fun of(preferredLanguages: List<String>): VoiceLanguage {
            val vietnamese = preferredLanguages.any { tag ->
                tag.split('-', '_').firstOrNull { it.isNotEmpty() }?.lowercase() == "vi"
            }
            return if (vietnamese) VIETNAMESE else ENGLISH
        }

        /** The user's choice, or the default for [preferredLanguages] when there is none (or it is not one of the
         *  cases). */
        fun saved(settings: KeyValueStore, preferredLanguages: List<String>): VoiceLanguage {
            val stored = settings.getString(SETTINGS_KEY)
            return entries.firstOrNull { it.tag == stored } ?: of(preferredLanguages)
        }
    }
}
