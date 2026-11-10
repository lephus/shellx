package com.shellx.app.voice

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * How loud the voice is while the user talks, from 0 (silence) to 1, for the mic's rings and the level bar
 * (`AudioLevelMeter.swift`). The recognizer's `onRmsChanged` decibels map linearly from [RMS_FLOOR_DB] (0) to
 * [RMS_CEILING_DB] (1), clamped; back to 0 when a run stops. Thread-safe.
 */
class AudioLevelMeter(initial: Float = 0f) {
    private val _level = MutableStateFlow(initial.coerceIn(0f, 1f))
    val level: StateFlow<Float> = _level.asStateFlow()

    fun update(rmsDb: Float) {
        _level.value = if (rmsDb.isNaN()) 0f else ((rmsDb - RMS_FLOOR_DB) / (RMS_CEILING_DB - RMS_FLOOR_DB)).coerceIn(0f, 1f)
    }

    fun reset() {
        _level.value = 0f
    }

    companion object {
        const val RMS_FLOOR_DB = -2f
        const val RMS_CEILING_DB = 10f
    }
}
