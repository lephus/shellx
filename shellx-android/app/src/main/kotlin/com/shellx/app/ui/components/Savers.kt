package com.shellx.app.ui.components

import androidx.compose.runtime.saveable.Saver
import com.shellx.core.link.SessionRef
import com.shellx.core.text.cutToUtf8
import com.shellx.core.workspaces.WorkspaceRef

/** Keeps a dialog's or sheet's target across recreation (Review Focus 1): `rememberSaveable(stateSaver = …)`. */
val WorkspaceRefSaver: Saver<WorkspaceRef?, Any> = Saver(
    save = { ref -> ref?.let { arrayListOf(it.machineId, it.workspaceId) } },
    restore = { saved ->
        (saved as? List<*>)?.let { WorkspaceRef(it[0] as String, it[1] as String) }
    },
)

/**
 * At most this many UTF-8 bytes of a field's text go into the saved screen state. A huge paste would otherwise overflow
 * what the system keeps for the app when it goes to the background (`TransactionTooLargeException`). Text this long is
 * far over every send limit, and the field's counter already says so.
 */
const val SAVED_TEXT_LIMIT: Int = 65_536

/** A field's typed text across recreation (Review Focus 3), cut to its first [SAVED_TEXT_LIMIT] bytes. */
val SavedTextSaver: Saver<String, String> = Saver(save = { it.cutToUtf8(SAVED_TEXT_LIMIT) }, restore = { it })

/** Typed texts by id across recreation, each cut to its first [SAVED_TEXT_LIMIT] bytes. */
val SavedTextMapSaver: Saver<Map<String, String>, HashMap<String, String>> = Saver(
    save = { texts -> HashMap(texts.mapValues { (_, text) -> text.cutToUtf8(SAVED_TEXT_LIMIT) }) },
    restore = { it },
)

val SessionRefSaver: Saver<SessionRef?, Any> = Saver(
    save = { ref -> ref?.let { arrayListOf(it.machineId, it.sessionId, it.agent, it.workspaceTitle) } },
    restore = { saved ->
        (saved as? List<*>)?.let { SessionRef(it[0] as String, it[1] as String, it[2] as String, it[3] as String) }
    },
)
