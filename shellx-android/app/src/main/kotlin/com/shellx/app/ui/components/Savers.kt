package com.shellx.app.ui.components

import androidx.compose.runtime.saveable.Saver
import com.shellx.core.link.SessionRef
import com.shellx.core.workspaces.WorkspaceRef

/** Keeps a dialog's or sheet's target across recreation (Review Focus 1): `rememberSaveable(stateSaver = …)`. */
val WorkspaceRefSaver: Saver<WorkspaceRef?, Any> = Saver(
    save = { ref -> ref?.let { arrayListOf(it.machineId, it.workspaceId) } },
    restore = { saved ->
        (saved as? List<*>)?.let { WorkspaceRef(it[0] as String, it[1] as String) }
    },
)

val SessionRefSaver: Saver<SessionRef?, Any> = Saver(
    save = { ref -> ref?.let { arrayListOf(it.machineId, it.sessionId, it.agent, it.workspaceTitle) } },
    restore = { saved ->
        (saved as? List<*>)?.let { SessionRef(it[0] as String, it[1] as String, it[2] as String, it[3] as String) }
    },
)
