package com.shellx.app.ui.workspaces

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.HomeFixtures.ref
import com.shellx.core.workspaces.WorkspaceCommandResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** What the list does with the Mac's answer to a command (WorkspaceListRenderTests' "What the Mac answered"). */
@RunWith(AndroidJUnit4::class)
class WorkspaceFeedbackTest {
    private val m = "m1"

    private fun of(result: WorkspaceCommandResult, command: WorkspaceCommand) = WorkspaceFeedback.of(result, command, m)

    private fun alert(kind: WorkspaceAlert) = WorkspaceFeedback.Alert(kind)

    @Test
    fun feedbackFollowsTheMacsAnswer() {
        val ok = WorkspaceCommandResult.Ok(null)
        assertEquals(WorkspaceFeedback.Open(ref("ws-new")), of(WorkspaceCommandResult.Ok("ws-new"), WorkspaceCommand.CREATE))
        assertEquals("the row arrives by push", WorkspaceFeedback.None, of(ok, WorkspaceCommand.CREATE))
        assertEquals(WorkspaceFeedback.None, of(ok, WorkspaceCommand.RENAME))
        assertEquals(WorkspaceFeedback.None, of(ok, WorkspaceCommand.CLOSE))
        for (command in listOf(WorkspaceCommand.CREATE, WorkspaceCommand.RENAME, WorkspaceCommand.CLOSE)) {
            assertEquals(WorkspaceFeedback.Refresh, of(WorkspaceCommandResult.NotFound, command))
            assertEquals(alert(WorkspaceAlert.OFFLINE), of(WorkspaceCommandResult.Offline, command))
            assertEquals(alert(WorkspaceAlert.FAILED), of(WorkspaceCommandResult.Failed, command))
            assertEquals(alert(WorkspaceAlert.UNKNOWN), of(WorkspaceCommandResult.Unknown, command))
        }
        assertEquals(alert(WorkspaceAlert.REFUSED_CLOSE), of(WorkspaceCommandResult.Refused, WorkspaceCommand.CLOSE))
        assertEquals(alert(WorkspaceAlert.REFUSED_CONTROL), of(WorkspaceCommandResult.Refused, WorkspaceCommand.CREATE))
        assertEquals(alert(WorkspaceAlert.REFUSED_CONTROL), of(WorkspaceCommandResult.Refused, WorkspaceCommand.RENAME))
        // Closing an agent: the session moves to Ended by push; an agent the Mac cannot close says so.
        assertEquals(WorkspaceFeedback.None, of(ok, WorkspaceCommand.CLOSE_AGENT))
        assertEquals(alert(WorkspaceAlert.AGENT_NOT_CLOSABLE), of(WorkspaceCommandResult.NotFound, WorkspaceCommand.CLOSE_AGENT))
        assertEquals(alert(WorkspaceAlert.REFUSED_CLOSE_AGENT), of(WorkspaceCommandResult.Refused, WorkspaceCommand.CLOSE_AGENT))
        assertEquals(alert(WorkspaceAlert.OFFLINE), of(WorkspaceCommandResult.Offline, WorkspaceCommand.CLOSE_AGENT))
        assertEquals(alert(WorkspaceAlert.FAILED), of(WorkspaceCommandResult.Failed, WorkspaceCommand.CLOSE_AGENT))
        assertEquals(alert(WorkspaceAlert.UNKNOWN), of(WorkspaceCommandResult.Unknown, WorkspaceCommand.CLOSE_AGENT))
        // Closing a tab: the tab (or its workspace) leaves by push; a tab the Mac no longer has says so.
        assertEquals(WorkspaceFeedback.None, of(ok, WorkspaceCommand.CLOSE_TAB))
        assertEquals(alert(WorkspaceAlert.TAB_NOT_CLOSABLE), of(WorkspaceCommandResult.NotFound, WorkspaceCommand.CLOSE_TAB))
        assertEquals(alert(WorkspaceAlert.REFUSED_CLOSE_TAB), of(WorkspaceCommandResult.Refused, WorkspaceCommand.CLOSE_TAB))
        assertEquals(alert(WorkspaceAlert.OFFLINE), of(WorkspaceCommandResult.Offline, WorkspaceCommand.CLOSE_TAB))
        assertEquals(alert(WorkspaceAlert.FAILED), of(WorkspaceCommandResult.Failed, WorkspaceCommand.CLOSE_TAB))
        assertEquals(alert(WorkspaceAlert.UNKNOWN), of(WorkspaceCommandResult.Unknown, WorkspaceCommand.CLOSE_TAB))
    }

    @Test
    fun everyAlertSaysSomethingDifferent() {
        val context: Context = ApplicationProvider.getApplicationContext()
        val messages = WorkspaceAlert.entries.map { context.getString(it.message) }
        assertEquals(9, WorkspaceAlert.entries.size)
        assertEquals(WorkspaceAlert.entries.size, messages.toSet().size)
        for (message in messages) assertTrue(message.isNotEmpty())
    }
}
