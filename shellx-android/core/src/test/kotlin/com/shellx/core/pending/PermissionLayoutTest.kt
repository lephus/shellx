package com.shellx.core.pending

import kotlin.test.Test
import kotlin.test.assertEquals

/** How a permission card lays out its actions (ruling P3-R4): a lasting grant is never the one-tap button. */
class PermissionLayoutTest {
    @Test fun allowAndDenyStayInTheRow() {
        val all = PermissionLayout.of(listOf(PendingAction.AllowOnce, PendingAction.Deny, PendingAction.AllowAlways, PendingAction.AllowAllTools))
        assertEquals(listOf(PendingAction.Deny, PendingAction.AllowOnce), all.buttons)
        assertEquals(listOf(PendingAction.AllowAlways, PendingAction.AllowAllTools), all.menu)
        assertEquals(listOf(PendingAction.Deny), PermissionLayout.of(listOf(PendingAction.Deny)).buttons)
        assertEquals(emptyList(), PermissionLayout.of(listOf(PendingAction.Deny)).menu)
    }

    @Test fun lastingGrantIsNeverTheOneTapButton() {
        val noOnce = PermissionLayout.of(listOf(PendingAction.Deny, PendingAction.AllowAlways, PendingAction.AllowAllTools))
        assertEquals(listOf(PendingAction.Deny), noOnce.buttons, "without Allow (once) the row has Deny only")
        assertEquals(listOf(PendingAction.AllowAlways, PendingAction.AllowAllTools), noOnce.menu, "lasting grants stay one step away")
        val alwaysOnly = PermissionLayout.of(listOf(PendingAction.AllowAlways))
        assertEquals(emptyList(), alwaysOnly.buttons)
        assertEquals(listOf(PendingAction.AllowAlways), alwaysOnly.menu)
        val allToolsOnly = PermissionLayout.of(listOf(PendingAction.AllowAllTools, PendingAction.Deny))
        assertEquals(listOf(PendingAction.Deny), allToolsOnly.buttons)
        assertEquals(listOf(PendingAction.AllowAllTools), allToolsOnly.menu)
    }

    @Test fun onlyPermissionActionsAreLaidOut() {
        val layout = PermissionLayout.of(listOf(PendingAction.Answer, PendingAction.OpenOnMac, PendingAction.RejectPlan, PendingAction.AllowOnce))
        assertEquals(listOf(PendingAction.AllowOnce), layout.buttons)
        assertEquals(emptyList(), layout.menu)
    }
}
