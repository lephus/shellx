package com.shellx.core.home

import com.shellx.core.composer.OutgoingAttachment
import com.shellx.core.text.utf8Size
import com.shellx.link.core.ShellXLink

/**
 * Whether the composer's message may be sent: its text trimmed at both ends and at most [MAX_BYTES] UTF-8 bytes, the
 * `chat.send` limit (PROTOCOL.md), with at most ShellXLink.MAX_ATTACHMENTS_PER_MESSAGE attachments of at most
 * ShellXLink.MAX_ATTACHMENT_BYTES each. A message needs text or an attachment. Checked on the phone, so the Mac never
 * has to answer a protocol error. Neither the text nor a name ever prints.
 */
sealed interface ComposerValidation {
    /** Nothing but whitespace, and no attachment: nothing to do. */
    data object Empty : ComposerValidation

    /** The trimmed text, ready to send; empty for a message of attachments only. */
    data class Ok(val text: String) : ComposerValidation {
        override fun toString(): String = "Ok(text=<redacted>)"
    }

    /** Too long to send; [bytes] is the trimmed text's UTF-8 length. */
    data class TooLong(val bytes: Int) : ComposerValidation

    /** More attachments than one message carries. */
    data object TooManyAttachments : ComposerValidation

    /** The attachment called [name] is bigger than one upload may be. */
    data class AttachmentTooLarge(val name: String) : ComposerValidation {
        override fun toString(): String = "AttachmentTooLarge(name=<redacted>)"
    }

    companion object {
        /** The most UTF-8 bytes one `chat.send` carries. */
        const val MAX_BYTES = 16_384

        /** The text, with [attachmentCount] attachments: empty text is Ok("") when there is at least one. Their sizes
         *  are [check]'s. */
        fun of(text: String, attachmentCount: Int = 0): ComposerValidation {
            val trimmed = text.trim()
            val bytes = trimmed.utf8Size
            return when {
                bytes > MAX_BYTES -> TooLong(bytes)
                attachmentCount > ShellXLink.MAX_ATTACHMENTS_PER_MESSAGE -> TooManyAttachments
                bytes == 0 && attachmentCount == 0 -> Empty
                else -> Ok(trimmed)
            }
        }

        /** Why [attachments] cannot go with one message (too many, or the first one too big); null when they can. */
        fun check(attachments: List<OutgoingAttachment>): ComposerValidation? {
            if (attachments.size > ShellXLink.MAX_ATTACHMENTS_PER_MESSAGE) return TooManyAttachments
            val big = attachments.firstOrNull { it.data.size > ShellXLink.MAX_ATTACHMENT_BYTES } ?: return null
            return AttachmentTooLarge(big.name)
        }

        /** The text and the attachments together: the first reason not to send them, or Ok. What the composer and the
         *  models check before any call. */
        fun message(text: String, attachments: List<OutgoingAttachment>): ComposerValidation {
            val validation = of(text, attachments.size)
            if (validation !is Ok) return validation
            return check(attachments) ?: validation
        }
    }
}
