package com.shellx.core.agent

import com.shellx.core.home.ComposerValidation
import com.shellx.link.core.ChatSendOutcome

/** What became of a message sent from an agent's screen. */
sealed interface AgentSendResult {
    /** Not sent: the text is empty, or longer than one `chat.send` carries, or the attachments are too many or one is
     *  too big. */
    data class Refused(val validation: ComposerValidation) : AgentSendResult

    /** The Mac's answer. */
    data class Sent(val outcome: ChatSendOutcome) : AgentSendResult

    /** The session's Mac is not online: nothing was sent or queued (spec section 7.5). */
    data object Offline : AgentSendResult

    /** A message with attachments that surely did not reach the session: an upload failed (the link dropped, or the
     *  Mac refused it), or the Mac refused the message that named them. Nothing was typed; it can be sent again. */
    data object NotSent : AgentSendResult

    /** A message with attachments that the Mac no longer takes them for (`unsupported`): nothing was typed, and
     *  sending it again will not help until the Mac takes attachments again. */
    data object AttachmentsUnsupported : AgentSendResult

    /** The link failed before the Mac answered: the text may or may not have arrived. */
    data object NoAnswer : AgentSendResult

    /**
     * True when the Mac surely did not take the message, so the composer gets its text and attachments back to send
     * again. Never after `submitted` or no answer, where sending again could deliver it twice.
     */
    val keepsDraft: Boolean
        get() = when (this) {
            is Refused -> validation is ComposerValidation.TooLong || validation == ComposerValidation.TooManyAttachments ||
                validation is ComposerValidation.AttachmentTooLarge
            is Sent -> outcome != ChatSendOutcome.SUBMITTED
            Offline, NotSent, AttachmentsUnsupported -> true
            NoAnswer -> false
        }
}
