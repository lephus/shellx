package com.shellx.app.ui.update

import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.shellx.app.R
import com.shellx.app.platform.PlayUpdateChecker
import com.shellx.core.update.UpdatePrompt
import kotlinx.coroutines.flow.StateFlow

/**
 * The update prompt (`UpdateAlert.swift`; ledger A-27). Each offer starts Play's flexible-update dialog once
 * ([UpdatePrompt.update]: Play's "Update / No thanks" is the prompt). Once the download finished, a Snackbar says so and
 * offers Restart ([restart]: Play installs and restarts the app). [prompt] null (debug builds, the demo) shows nothing.
 * [restart] comes last, so a call can pass it as a trailing lambda.
 */
@Composable
fun UpdateAlert(
    prompt: UpdatePrompt?,
    installs: StateFlow<PlayUpdateChecker.InstallPhase>?,
    modifier: Modifier = Modifier,
    restart: () -> Unit,
) {
    if (prompt != null) {
        val offered by prompt.offered.collectAsStateWithLifecycle()
        // update() hides the offer, so the key changes to null and the dialog is started once per offer.
        LaunchedEffect(prompt, offered) { if (offered != null) prompt.update() }
    }
    val downloaded = installs?.collectAsStateWithLifecycle()?.value == PlayUpdateChecker.InstallPhase.DOWNLOADED
    val snackbar = remember { SnackbarHostState() }
    val message = stringResource(R.string.update_downloaded)
    val action = stringResource(R.string.update_restart)
    val currentRestart by rememberUpdatedState(restart)
    LaunchedEffect(downloaded, message, action) {
        if (!downloaded) return@LaunchedEffect
        val result = snackbar.showSnackbar(message, actionLabel = action, duration = SnackbarDuration.Indefinite)
        if (result == SnackbarResult.ActionPerformed) currentRestart()
    }
    SnackbarHost(snackbar, modifier)
}
