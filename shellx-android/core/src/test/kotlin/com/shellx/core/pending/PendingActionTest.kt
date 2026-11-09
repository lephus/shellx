package com.shellx.core.pending

import com.shellx.link.core.ExitPlanMode
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.PendingItem
import com.shellx.link.core.PendingKind
import com.shellx.link.core.PendingQuestion
import com.shellx.link.core.PendingQuestionOption
import com.shellx.link.core.PermissionMode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Which buttons a pending card offers, from the item's `kind` and `modes` alone. */
class PendingActionTest {
    private fun item(
        kind: PendingKind,
        modes: List<String> = emptyList(),
        questions: List<PendingQuestion>? = null,
        preview: String? = null,
        plan: String? = null,
    ): PendingItem = PendingItem(
        requestId = "r1", kind = kind, agent = "claude", workspaceId = "ws", workspaceTitle = "shellx",
        toolName = "Bash", toolInputPreview = preview, createdAtMs = 1, modes = modes, questions = questions,
        planPreview = plan,
    )

    private fun question(id: String, options: List<String>, multiSelect: Boolean = false): PendingQuestion =
        PendingQuestion(
            id = id, prompt = "Pick one", multiSelect = multiSelect,
            options = options.map { PendingQuestionOption(it, it) },
        )

    @Test fun permissionButtonsFollowModesInOrder() {
        assertEquals(
            listOf(PendingAction.AllowOnce, PendingAction.Deny, PendingAction.AllowAlways, PendingAction.AllowAllTools),
            item(PendingKind.PERMISSION, modes = listOf("all", "deny", "always", "once")).actions,
        )
        assertEquals(listOf(PendingAction.AllowOnce, PendingAction.Deny), item(PendingKind.PERMISSION, modes = listOf("deny", "once")).actions)
        assertEquals(listOf(PendingAction.AllowAlways), item(PendingKind.PERMISSION, modes = listOf("always")).actions)
        assertEquals(LinkDecision.Permission(PermissionMode.ONCE), PendingAction.AllowOnce.decision)
        assertEquals(LinkDecision.Permission(PermissionMode.DENY), PendingAction.Deny.decision)
        assertEquals(LinkDecision.Permission(PermissionMode.ALWAYS), PendingAction.AllowAlways.decision)
        assertEquals(LinkDecision.Permission(PermissionMode.ALL), PendingAction.AllowAllTools.decision)
    }

    @Test fun bypassAndUnknownModesNeverShown() {
        assertEquals(
            listOf(PendingAction.AllowOnce, PendingAction.Deny),
            item(PendingKind.PERMISSION, modes = listOf("bypass", "once", "bypassPermissions", "yolo", "deny")).actions,
        )
        assertEquals(listOf(PendingAction.OpenOnMac), item(PendingKind.PERMISSION, modes = listOf("bypass", "bypassPermissions")).actions)
        assertEquals(
            listOf(PendingAction.ApprovePlan(ExitPlanMode.MANUAL)),
            item(PendingKind.EXIT_PLAN, modes = listOf("bypassPermissions", "manual", "later")).actions,
        )
    }

    @Test fun emptyModesOpenOnMac() {
        assertEquals(listOf(PendingAction.OpenOnMac), item(PendingKind.PERMISSION).actions)
        assertEquals(listOf(PendingAction.OpenOnMac), item(PendingKind.EXIT_PLAN, plan = "1. Do it").actions)
        assertNull(PendingAction.OpenOnMac.decision)
    }

    @Test fun questionWithoutOptionsOpenOnMac() {
        assertEquals(listOf(PendingAction.Answer), item(PendingKind.QUESTION, questions = listOf(question("q1", listOf("A", "B")))).actions)
        assertNull(PendingAction.Answer.decision, "the answer comes from the sheet")
        assertEquals(listOf(PendingAction.OpenOnMac), item(PendingKind.QUESTION).actions, "no questions at all")
        assertEquals(listOf(PendingAction.OpenOnMac), item(PendingKind.QUESTION, questions = emptyList()).actions)
        assertEquals(
            listOf(PendingAction.OpenOnMac),
            item(PendingKind.QUESTION, questions = listOf(question("q1", listOf("A")), question("q2", emptyList()))).actions,
            "one question has nothing to pick",
        )
    }

    @Test fun questionWithRepeatedIDsOpenOnMac() {
        // Answers are kept by question id: two questions sharing one could not be told apart.
        assertEquals(
            listOf(PendingAction.OpenOnMac),
            item(PendingKind.QUESTION, questions = listOf(question("q1", listOf("A")), question("q1", listOf("B")))).actions,
        )
        assertEquals(
            listOf(PendingAction.Answer),
            item(PendingKind.QUESTION, questions = listOf(question("q1", listOf("A")), question("q2", listOf("B")))).actions,
        )
    }

    @Test fun planApproveManualFirst() {
        assertEquals(
            listOf(
                PendingAction.ApprovePlan(ExitPlanMode.MANUAL), PendingAction.ApprovePlan(ExitPlanMode.AUTO_ACCEPT),
                PendingAction.ApprovePlan(ExitPlanMode.ULTRAPLAN), PendingAction.RevisePlan, PendingAction.RejectPlan,
            ),
            item(PendingKind.EXIT_PLAN, modes = listOf("ultraplan", "deny", "auto_accept", "manual")).actions,
        )
        assertEquals(listOf(PendingAction.ApprovePlan(ExitPlanMode.AUTO_ACCEPT)), item(PendingKind.EXIT_PLAN, modes = listOf("auto_accept")).actions)
        assertEquals(listOf(PendingAction.RevisePlan, PendingAction.RejectPlan), item(PendingKind.EXIT_PLAN, modes = listOf("deny")).actions)
        assertEquals(LinkDecision.ExitPlan(ExitPlanMode.MANUAL, feedback = null), PendingAction.ApprovePlan(ExitPlanMode.MANUAL).decision)
        assertEquals(LinkDecision.ExitPlan(ExitPlanMode.DENY, feedback = null), PendingAction.RejectPlan.decision)
        assertNull(PendingAction.RevisePlan.decision, "feedback comes from the sheet")
    }

    @Test fun unknownKindOpenOnMacOnly() {
        assertEquals(
            listOf(PendingAction.OpenOnMac),
            item(PendingKind("teleport"), modes = listOf("once", "deny", "manual"), questions = listOf(question("q1", listOf("A")))).actions,
        )
    }

    // What the card body shows

    @Test fun previewShowsCommandOutOfToolInput() {
        val bash = item(PendingKind.PERMISSION, preview = """{"command":"git push origin main","description":"Push"}""")
        assertEquals("git push origin main", bash.previewText)
        val edit = item(PendingKind.PERMISSION, preview = """{"file_path":"/tmp/a.swift","old_string":"a","new_string":"b"}""")
        assertEquals("/tmp/a.swift", edit.previewText)
    }

    @Test fun previewKeepsTextThatIsNotJSON() {
        // A preview cut at 8192 bytes is no longer valid JSON: it is shown as it came.
        val cut = """{"command":"echo """
        assertEquals(cut, item(PendingKind.PERMISSION, preview = cut).previewText)
        assertEquals("""{"other":1}""", item(PendingKind.PERMISSION, preview = """{"other":1}""").previewText)
        assertNull(item(PendingKind.PERMISSION).previewText)
    }

    @Test fun previewFieldsPutTheTellingOneFirst() {
        val edit = item(
            PendingKind.PERMISSION,
            preview = """{"new_string":"b","file_path":"/tmp/a.swift","old_string":"a","replace_all":false}""",
        )
        assertEquals(listOf("file_path", "new_string", "old_string", "replace_all"), edit.previewFields?.map { it.first })
        assertEquals("/tmp/a.swift", edit.previewFields?.first()?.second)
        assertEquals("false", edit.previewFields?.last()?.second)
        val nested = item(PendingKind.PERMISSION, preview = """{"command":"ls","env":{"A":"1"}}""")
        assertEquals("""{"A":"1"}""", nested.previewFields?.last()?.second)
        assertNull(item(PendingKind.PERMISSION, preview = "plain text").previewFields)
        assertNull(item(PendingKind.EXIT_PLAN, plan = """{"command":"ls"}""").previewFields, "only a tool's input has fields")
    }

    @Test fun previewMayBeCutAtEitherLimit() {
        assertTrue(PendingItem.previewMayBeCut("a".repeat(8192)))
        assertTrue(PendingItem.previewMayBeCut("ệ".repeat(2730)), "8190 bytes: the next didn't fit")
        assertTrue(PendingItem.previewMayBeCut("a".repeat(1024)))
        assertFalse(PendingItem.previewMayBeCut("a".repeat(4000)))
        assertFalse(PendingItem.previewMayBeCut("git status"))
    }

    @Test fun previewOfQuestionAndPlan() {
        val two = item(PendingKind.QUESTION, questions = listOf(question("q1", listOf("A")), question("q2", listOf("B"))))
        assertEquals("Pick one\nPick one", two.previewText)
        assertEquals("1. Step", item(PendingKind.EXIT_PLAN, plan = "1. Step").previewText)
    }
}
