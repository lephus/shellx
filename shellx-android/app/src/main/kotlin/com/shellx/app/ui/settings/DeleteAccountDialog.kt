package com.shellx.app.ui.settings

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.BasicAlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.shellx.app.R
import com.shellx.app.ui.signin.SignInErrorText
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.ui.theme.StatusTone
import com.shellx.app.ui.theme.color
import com.shellx.core.account.SignInException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * "Delete Account…" (S1 §6.8; 1C's `DeleteAccountSheet` without `switchFirst`: an Android session is always Google):
 * the question, then Google's sheet for a fresh sign-in and the deletion (Working), then a failure's words.
 * Main-confined.
 */
class DeleteAccountFlow(private val delete: suspend () -> Unit) {
    sealed interface Step {
        data object Confirm : Step

        data object Working : Step

        data class Failed(@StringRes val message: Int) : Step
    }

    private val _step = MutableStateFlow<Step>(Step.Confirm)
    val step: StateFlow<Step> = _step.asStateFlow()

    /**
     * Does nothing while Working. Working; then success stays Working (the screen goes as the account signs out);
     * SignInException.Cancelled → Confirm; another SignInException → Failed(its words, or signin_error_server); any
     * other failure → Failed(signin_error_server). A caller cancelled meanwhile puts the question back (the deletion
     * itself runs on, detached, in the coordinator, and a new tap joins it).
     */
    suspend fun run() {
        if (_step.value == Step.Working) return
        _step.value = Step.Working
        try {
            delete()
        } catch (e: CancellationException) {
            _step.value = Step.Confirm
            throw e
        } catch (e: SignInException) {
            _step.value = if (e is SignInException.Cancelled) {
                Step.Confirm
            } else {
                Step.Failed(SignInErrorText.message(e) ?: R.string.signin_error_server)
            }
        } catch (_: Exception) {
            _step.value = Step.Failed(R.string.signin_error_server)
        }
    }
}

/**
 * The deletion's card (a dialog's content; rendered directly in tests): the warning, the title, what is lost, a
 * failure's words in a polite live region, then Cancel and Delete Account. Working shows [spinner] and "Deleting…" in
 * place of the words and turns both buttons off. [spinner] is a still one in renders.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DeleteAccountCard(
    step: DeleteAccountFlow.Step,
    onDelete: () -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
    spinner: @Composable (Modifier) -> Unit = { CircularProgressIndicator(it, color = LocalContentColor.current, strokeWidth = 2.dp) },
) {
    val working = step == DeleteAccountFlow.Step.Working
    val error = StatusTone.ERROR.color()
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(28.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
    ) {
        Column(
            modifier = Modifier.padding(24.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Icon(
                Icons.Filled.Warning,
                contentDescription = null,
                tint = error,
                modifier = Modifier.align(Alignment.CenterHorizontally),
            )
            Text(
                text = stringResource(R.string.settings_account_delete_title),
                modifier = Modifier.fillMaxWidth().semantics { heading() },
                style = MaterialTheme.typography.headlineSmall,
                color = MaterialTheme.colorScheme.onSurface,
                textAlign = TextAlign.Center,
            )
            if (working) {
                Row(
                    modifier = Modifier.semantics(mergeDescendants = true) {}.testTag("delete.working"),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    spinner(Modifier.size(20.dp))
                    Text(
                        text = stringResource(R.string.settings_account_delete_deleting),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                Text(
                    text = stringResource(R.string.settings_account_delete_message),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (step is DeleteAccountFlow.Step.Failed) {
                Text(
                    text = stringResource(step.message),
                    modifier = Modifier.testTag("delete.error").semantics { liveRegion = LiveRegionMode.Polite },
                    style = MaterialTheme.typography.bodyMedium,
                    color = error,
                )
            }
            FlowRow(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
            ) {
                TextButton(onClick = onCancel, enabled = !working, modifier = Modifier.testTag("delete.cancel")) {
                    Text(stringResource(R.string.common_cancel), color = if (working) LocalContentColor.current else ShellXTheme.colors.accentText)
                }
                TextButton(onClick = onDelete, enabled = !working, modifier = Modifier.testTag("delete.confirm")) {
                    Text(stringResource(R.string.settings_account_delete_button), color = if (working) LocalContentColor.current else error)
                }
            }
        }
    }
}

/**
 * The card in a dialog. Dismissing it (Cancel, Back, a tap outside) does nothing while it deletes. Delete runs
 * [DeleteAccountFlow.run] in [scope] (Settings passes its ViewModel's, so a rotation keeps it).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DeleteAccountDialog(flow: DeleteAccountFlow, onDismiss: () -> Unit, scope: CoroutineScope = rememberCoroutineScope()) {
    val step by flow.step.collectAsStateWithLifecycle()
    val dismiss = { if (flow.step.value != DeleteAccountFlow.Step.Working) onDismiss() }
    BasicAlertDialog(onDismissRequest = dismiss) {
        DeleteAccountCard(step = step, onDelete = { scope.launch { flow.run() } }, onCancel = dismiss)
    }
}
