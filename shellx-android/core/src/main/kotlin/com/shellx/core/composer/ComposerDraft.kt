package com.shellx.core.composer

/**
 * The message a screen's composer holds: its text and attachments, and the message with attachments on its way, if
 * any. Immutable: the screen edits text and attachments with copy().
 *
 * A message with attachments stays in the composer while it is sent; the composer is locked meanwhile. When the answer
 * comes, its text and the attachments that went are cleared, unless the result keeps the draft to send again. An
 * attachment added meanwhile (a photo that finished loading after Send was tapped) was never sent, so it stays for the
 * next message.
 */
data class ComposerDraft(
    val text: String = "",
    val attachments: List<OutgoingAttachment> = emptyList(),
    /** The ids of the attachments of the message on its way; null when none is. */
    private val inFlight: Set<String>? = null,
) {
    /** True from [sendStarted] to [sendEnded]. */
    val isSending: Boolean get() = inFlight != null

    /** The composer handed over its message with the attachments it holds now. */
    fun sendStarted(): ComposerDraft = copy(inFlight = attachments.map { it.id }.toSet())

    /** The answer came: unless [keepsDraft], the text and the attachments that went are cleared. */
    fun sendEnded(keepsDraft: Boolean): ComposerDraft {
        val sent = inFlight ?: return this
        if (keepsDraft) return copy(inFlight = null)
        return copy(text = "", attachments = attachments.filter { it.id !in sent }, inFlight = null)
    }

    override fun toString(): String = "ComposerDraft(text=<redacted>, attachments=$attachments, isSending=$isSending)"
}
