package com.shellx.app.ui.workspaces

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import java.util.UUID
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** A short line the list says once. The text may name a workspace, so it never prints. */
data class Notice(val text: String, val id: String = UUID.randomUUID().toString()) {
    override fun toString(): String = "Notice(text=<redacted>, id=$id)"
}

/**
 * A line the workspace list says once (`ListNotice.swift`), left there by a screen that went away on its own: the
 * workspace screen, popped because its workspace was closed on the Mac. The list shows it for [DURATION], then clears
 * it. Main-confined.
 */
class ListNotice {
    private val _current = MutableStateFlow<Notice?>(null)
    val current: StateFlow<Notice?> = _current.asStateFlow()

    fun show(text: String) {
        _current.value = Notice(text)
    }

    /** Clears the notice [id]; a newer one stays. */
    fun clear(id: String) {
        if (_current.value?.id == id) _current.value = null
    }

    companion object {
        /** How long a notice shows (the iPhone's `AgentView.noticeDuration`). */
        val DURATION: Duration = 4.seconds
    }
}

/** The notice as the list (and plan 3E's agent screen) shows it: a capsule over the bottom edge, read out politely. */
@Composable
fun NoticeCapsule(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        modifier = modifier
            .padding(vertical = 6.dp)
            .background(MaterialTheme.colorScheme.surfaceContainerHighest, CircleShape)
            .padding(horizontal = 12.dp, vertical = 6.dp)
            .semantics { liveRegion = LiveRegionMode.Polite }
            .testTag("workspaces.notice"),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurface,
    )
}
