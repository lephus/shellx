@file:OptIn(ExperimentalCoroutinesApi::class)

package com.shellx.app.ui.settings

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.core.account.SignInException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/** S1 §6.8's steps: the question, then Google's sheet and the deletion (Working), then what a failure says. */
@RunWith(AndroidJUnit4::class)
class DeleteAccountFlowTest {
    @Test
    fun aDeletionThatWorksStaysWorking() {
        runTest {
            val flow = DeleteAccountFlow {}
            assertEquals(DeleteAccountFlow.Step.Confirm, flow.step.value)

            flow.run()

            assertEquals("the screen goes as the account signs out", DeleteAccountFlow.Step.Working, flow.step.value)
        }
    }

    @Test
    fun closingTheGoogleSheetGoesBackToTheQuestion() {
        runTest {
            val flow = DeleteAccountFlow { throw SignInException.Cancelled() }

            flow.run()

            assertEquals(DeleteAccountFlow.Step.Confirm, flow.step.value)
        }
    }

    @Test
    fun aRefusedReauthenticationSaysWhy() {
        runTest {
            val refused = DeleteAccountFlow { throw SignInException.ReauthRequired() }
            refused.run()
            assertEquals(DeleteAccountFlow.Step.Failed(R.string.signin_error_reauth_required), refused.step.value)

            val broken = DeleteAccountFlow { throw IllegalStateException() }
            broken.run()
            assertEquals(DeleteAccountFlow.Step.Failed(R.string.signin_error_server), broken.step.value)
        }
    }

    @Test
    fun deleteTappedTwiceDeletesOnce() {
        runTest {
            val gate = CompletableDeferred<Unit>()
            var calls = 0
            val flow = DeleteAccountFlow {
                calls++
                gate.await()
            }

            val first = launch { flow.run() }
            val second = launch { flow.run() }
            runCurrent()
            assertEquals(DeleteAccountFlow.Step.Working, flow.step.value)
            gate.complete(Unit)
            first.join()
            second.join()

            assertEquals("one request", 1, calls)
            assertEquals(DeleteAccountFlow.Step.Working, flow.step.value)
        }
    }
}
