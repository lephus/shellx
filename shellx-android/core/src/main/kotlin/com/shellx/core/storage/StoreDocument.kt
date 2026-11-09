package com.shellx.core.storage

import com.shellx.core.link.SessionRef

/** One document the phone keeps on disk: one session's chat copy. */
sealed interface StoreDocument {
    data class Thread(val ref: SessionRef) : StoreDocument {
        override val kind: String get() = "thread"
    }

    /** Short name for logs; never includes ids or content. */
    val kind: String
}
