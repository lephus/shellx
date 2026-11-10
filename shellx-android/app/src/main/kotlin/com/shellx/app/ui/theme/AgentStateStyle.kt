package com.shellx.app.ui.theme

import android.content.res.Resources
import android.icu.text.MeasureFormat
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import android.icu.util.ULocale
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color
import com.shellx.app.R
import com.shellx.core.home.AgentStatusRow
import com.shellx.link.core.AgentState
import java.util.Locale
import kotlin.time.Duration
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.seconds

/** The status colours (the iPhone's `Status*` colour sets). Running is yellow. */
enum class StatusTone { DONE, ERROR, IDLE, NEEDS_YOU, RUNNING }

/** The tone's colour in the current theme: the only way screens pick a status colour. */
@Composable
@ReadOnlyComposable
fun StatusTone.color(): Color {
    val colors = ShellXTheme.colors
    return when (this) {
        StatusTone.DONE -> colors.statusDone
        StatusTone.ERROR -> colors.statusError
        StatusTone.IDLE -> colors.statusIdle
        StatusTone.NEEDS_YOU -> colors.statusNeedsYou
        StatusTone.RUNNING -> colors.statusRunning
    }
}

/**
 * How a session's state looks in the agent screen's header and the pane chips (`AgentStateStyle.swift`): the words
 * always carry the state, so the colour is never the only cue. A state this app does not know shows neither.
 * [shortText] is what a chip has room for: "4 minutes" instead of "Running for 4 minutes".
 */
data class AgentStateStyle(val text: String?, val shortText: String?, val tone: StatusTone?) {
    companion object {
        fun of(row: AgentStatusRow, res: Resources): AgentStateStyle {
            if (!row.online) {
                // The last known state of a Mac that is not online: grey, and it says so.
                val text = res.getString(R.string.agent_state_offline)
                return AgentStateStyle(text, text, StatusTone.IDLE)
            }
            return when (row.state) {
                AgentState.NEEDS_INPUT -> res.getString(R.string.agent_state_needs_you).let {
                    AgentStateStyle(it, it, StatusTone.NEEDS_YOU)
                }
                AgentState.WORKING -> {
                    val running = res.getString(R.string.agent_state_running)
                    val elapsed = row.elapsed?.let { elapsedText(it, AppLanguage.of(res.configuration.locales[0])) }
                    AgentStateStyle(
                        text = elapsed?.let { res.getString(R.string.agent_state_running_for, it) } ?: running,
                        shortText = elapsed ?: running,
                        tone = StatusTone.RUNNING,
                    )
                }
                AgentState.IDLE -> res.getString(R.string.agent_state_done).let { AgentStateStyle(it, it, StatusTone.DONE) }
                // Only the agent screen shows an ended session; the home lists live ones.
                AgentState.ENDED -> res.getString(R.string.agent_state_ended).let { AgentStateStyle(it, it, StatusTone.IDLE) }
                else -> AgentStateStyle(null, null, null)
            }
        }

        /**
         * "4 minutes", "1 hour, 5 minutes" (hours and minutes, at most two units, minutes rounded down), or seconds
         * under a minute, wide, in [locale] (the app's language, not the region's).
         */
        fun elapsedText(elapsed: Duration, locale: Locale): String {
            val format = MeasureFormat.getInstance(ULocale.forLocale(locale), MeasureFormat.FormatWidth.WIDE)
            if (elapsed < 60.seconds) return format.format(Measure(elapsed.inWholeSeconds, MeasureUnit.SECOND))
            val hours = elapsed.inWholeHours
            val minutes = (elapsed - hours.hours).inWholeMinutes
            val measures = buildList {
                if (hours > 0) add(Measure(hours, MeasureUnit.HOUR))
                if (minutes > 0 || hours == 0L) add(Measure(minutes, MeasureUnit.MINUTE))
            }
            return format.formatMeasures(*measures.toTypedArray())
        }
    }
}
