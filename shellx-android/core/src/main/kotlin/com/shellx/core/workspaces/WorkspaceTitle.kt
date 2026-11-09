package com.shellx.core.workspaces

import com.shellx.core.text.dropLastGrapheme
import com.shellx.core.text.nfc
import com.shellx.core.text.takeGraphemes
import com.shellx.core.text.utf8Size
import com.shellx.link.core.ShellXLink

/** A workspace name as the phone sends it in `workspace.rename` (PROTOCOL.md section 10). */
object WorkspaceTitle {
    /** The most characters the rename field takes. Characters are not bytes: a decomposed "ệ" is 5 UTF-8 bytes and a
     *  family emoji 25, so [cleaned] also cuts to `ShellXLink.MAX_WORKSPACE_TITLE_BYTES`. */
    const val MAX_CHARACTERS = 128

    /**
     * [title] as sent: surrounding spaces and line breaks gone, in composed form (NFC, the shortest for Vietnamese),
     * at most MAX_CHARACTERS characters, and cut on a character boundary to `ShellXLink.MAX_WORKSPACE_TITLE_BYTES`
     * UTF-8 bytes, so the Mac never refuses it for its size.
     */
    fun cleaned(title: String): String {
        var name = title.trim().nfc().takeGraphemes(MAX_CHARACTERS)
        while (name.utf8Size > ShellXLink.MAX_WORKSPACE_TITLE_BYTES) name = name.dropLastGrapheme()
        // A cut can end on a space.
        return name.trim()
    }

    /** Whether [title] can be sent: not empty once cleaned (an empty name would only mean "go back to the automatic
     *  one", which the phone does not offer). */
    fun canSave(title: String): Boolean = cleaned(title).isNotEmpty()
}
