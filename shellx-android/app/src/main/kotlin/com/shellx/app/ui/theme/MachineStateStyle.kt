package com.shellx.app.ui.theme

import android.content.res.Resources
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.core.link.MachineLinkState

/** How a Mac's link state looks (`MachineStateStyle.swift`): the dot's tone and the words next to it. */
data class MachineStateStyle(val text: String, val tone: StatusTone) {
    companion object {
        fun of(state: MachineLinkState, machineName: String, res: Resources): MachineStateStyle = when (state) {
            MachineLinkState.Online -> MachineStateStyle(res.getString(R.string.machine_state_online), StatusTone.DONE)
            MachineLinkState.Connecting, MachineLinkState.Reconnecting ->
                MachineStateStyle(res.getString(R.string.machine_state_connecting), StatusTone.RUNNING)
            is MachineLinkState.Offline ->
                MachineStateStyle(res.getString(R.string.machine_state_offline, machineName), StatusTone.IDLE)
            MachineLinkState.Revoked -> MachineStateStyle(res.getString(R.string.machine_state_revoked), StatusTone.ERROR)
            MachineLinkState.HostKeyChanged ->
                MachineStateStyle(res.getString(R.string.machine_state_host_key_changed), StatusTone.ERROR)
            MachineLinkState.NeedsUpdate ->
                MachineStateStyle(res.getString(R.string.machine_state_needs_update), StatusTone.NEEDS_YOU)
        }
    }
}

/** The small status dot in front of a state's words: 8 dp, scaled with the text; TalkBack skips it. */
@Composable
fun StatusDot(color: Color, modifier: Modifier = Modifier) {
    val size = (8 * LocalDensity.current.fontScale).dp
    Spacer(modifier.size(size).background(color, CircleShape))
}
