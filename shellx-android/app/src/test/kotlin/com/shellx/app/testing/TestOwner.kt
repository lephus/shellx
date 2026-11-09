package com.shellx.app.testing

import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry

/** A [LifecycleOwner] the test moves (made with [LifecycleRegistry.createUnsafe], so any thread may): CREATED until
 *  [start]. */
class TestOwner : LifecycleOwner {
    private val registry = LifecycleRegistry.createUnsafe(this).apply { currentState = Lifecycle.State.CREATED }

    override val lifecycle: Lifecycle get() = registry

    fun start() {
        registry.currentState = Lifecycle.State.STARTED
    }
}
