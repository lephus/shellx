package com.shellx.app.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.shellx.app.R
import com.shellx.app.ui.components.ConfirmDialog
import com.shellx.app.ui.theme.StatusTone
import com.shellx.app.ui.theme.color
import com.shellx.core.platform.CoreLog
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What Settings › Account can do; null in the demo (only the e-mail row shows). Both run detached in the
 *  coordinator (`AppCoordinator.signOut`/`deleteAccount`), so a repeat call joins the one under way. */
class AccountActions(val signOut: suspend () -> Unit, val deleteAccount: suspend () -> Unit)

/**
 * Sign-out and deletion progress, kept across a recreated Settings (carry 3D-3; the coordinator has no busy flow): a
 * rotation keeps the row's spinner and the deletion card's step, and a second tap never sends a second request. The
 * work runs in [viewModelScope]; the coordinator runs it detached, so leaving the page never cuts it short.
 * Main-confined.
 */
internal class AccountProgress : ViewModel() {
    private val _signingOut = MutableStateFlow(false)
    val signingOut: StateFlow<Boolean> = _signingOut.asStateFlow()

    private val _deletion = MutableStateFlow<DeleteAccountFlow?>(null)

    /** The open deletion card's flow; null while it is closed. */
    val deletion: StateFlow<DeleteAccountFlow?> = _deletion.asStateFlow()

    /** The latest delete action of the page that shows the card (a recreated page hands over its own). */
    var delete: suspend () -> Unit = {}

    /** Does nothing while a sign-out is under way. */
    fun signOut(signOut: suspend () -> Unit) {
        if (_signingOut.value) return
        _signingOut.value = true
        viewModelScope.launch {
            try {
                signOut()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                CoreLog.log("sign_out_failed")
            } finally {
                _signingOut.value = false
            }
        }
    }

    /** Opens the card on the question; one already open stays as it is. */
    fun openDeletion() {
        if (_deletion.value == null) _deletion.value = DeleteAccountFlow { delete() }
    }

    /** Closes the card, unless it is deleting. */
    fun closeDeletion() {
        if (_deletion.value?.step?.value != DeleteAccountFlow.Step.Working) _deletion.value = null
    }
}

/**
 * Settings › Account (`AccountSection.swift`, Google only): the e-mail (selectable), then, outside the demo, Sign out
 * (asks first; a spinner and off while it runs) and Delete Account… (the deletion card, S1 §6.8).
 */
@Composable
fun AccountSection(email: String, account: AccountActions?) {
    val progress = viewModel { AccountProgress() }
    val signingOut by progress.signingOut.collectAsStateWithLifecycle()
    val deletion by progress.deletion.collectAsStateWithLifecycle()
    var confirming by rememberSaveable { mutableStateOf(false) }
    if (account != null) SideEffect { progress.delete = account.deleteAccount }
    val error = StatusTone.ERROR.color()

    SettingsSection(title = stringResource(R.string.settings_account_title)) {
        ListItem(
            headlineContent = { Text(stringResource(R.string.signin_email)) },
            modifier = Modifier.semantics(mergeDescendants = true) {},
            trailingContent = {
                SelectionContainer {
                    Text(email, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            },
            colors = settingsRowColors(),
        )
        if (account != null) {
            SettingsDivider()
            ListItem(
                headlineContent = { Text(stringResource(R.string.settings_account_sign_out), color = error) },
                modifier = Modifier.clickable(enabled = !signingOut) { confirming = true }.testTag("settings.signOut"),
                trailingContent = if (signingOut) {
                    { CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) }
                } else {
                    null
                },
                colors = settingsRowColors(),
            )
            SettingsDivider()
            ListItem(
                headlineContent = { Text(stringResource(R.string.settings_account_delete), color = error) },
                modifier = Modifier.clickable(onClick = progress::openDeletion).testTag("settings.delete"),
                colors = settingsRowColors(),
            )
        }
    }

    if (account != null && confirming && !signingOut) {
        ConfirmDialog(
            title = stringResource(R.string.settings_account_sign_out),
            text = stringResource(R.string.settings_account_sign_out_confirm),
            confirmLabel = stringResource(R.string.settings_account_sign_out),
            onConfirm = { progress.signOut(account.signOut) },
            onDismiss = { confirming = false },
        )
    }
    val flow = deletion
    if (account != null && flow != null) {
        DeleteAccountDialog(flow, onDismiss = progress::closeDeletion, scope = progress.viewModelScope)
    }
}
