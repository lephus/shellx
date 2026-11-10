package com.shellx.app.testing

import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.activity.result.contract.ActivityResultContract
import androidx.core.app.ActivityOptionsCompat

/**
 * An [ActivityResultRegistry] that launches nothing: it records each launch and answers at once with [answer] when
 * set, else holds the launch until [answerLast].
 */
class FakeResultRegistry : ActivityResultRegistry() {
    data class Launch(val requestCode: Int, val contract: ActivityResultContract<*, *>, val input: Any?)

    private val made = mutableListOf<Launch>()

    /** Every launch, in order. */
    val launches: List<Launch> get() = made.toList()

    /** Answers each launch at once with what it returns; null holds the launch for [answerLast]. */
    var answer: ((Launch) -> Any?)? = null

    /** Thrown by the next launches instead of launching (no activity to start the prompt, say). */
    var failure: RuntimeException? = null

    override fun <I, O> onLaunch(
        requestCode: Int,
        contract: ActivityResultContract<I, O>,
        input: I,
        options: ActivityOptionsCompat?,
    ) {
        failure?.let { throw it }
        val launch = Launch(requestCode, contract, input)
        made += launch
        answer?.let { dispatchResult(requestCode, it(launch)) }
    }

    /** Answers the last launch with [result]. */
    fun answerLast(result: Any?) {
        dispatchResult(made.last().requestCode, result)
    }

    /** For `LocalActivityResultRegistryOwner` in Compose tests. */
    val owner: ActivityResultRegistryOwner = object : ActivityResultRegistryOwner {
        override val activityResultRegistry: ActivityResultRegistry get() = this@FakeResultRegistry
    }
}
