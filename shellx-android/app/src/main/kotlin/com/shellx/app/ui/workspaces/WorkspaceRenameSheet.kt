package com.shellx.app.ui.workspaces

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.components.TapOutsideHidesKeyboard
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.text.takeGraphemes
import com.shellx.core.workspaces.WorkspaceTitle

/** The iPhone's rename sheet as a bottom sheet (S3 §7.2): [WorkspaceRenameContent]. Plan 3E's workspace screen reuses
 *  it. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkspaceRenameSheet(current: String, save: (String) -> Unit, cancel: () -> Unit) {
    ModalBottomSheet(onDismissRequest = cancel, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        // The sheet's window is not the screen's: a tap on its own empty area puts the field's keyboard down here.
        TapOutsideHidesKeyboard { WorkspaceRenameContent(current, save, cancel) }
    }
}

/**
 * "Rename Workspace" (`WorkspaceRenameSheet.swift`): a field filled with the current name, Cancel and Save. Save is off
 * while the name, cleaned, is empty; it sends the cleaned name. The field takes at most
 * [WorkspaceTitle.MAX_CHARACTERS] characters and is focused when shown.
 */
@Composable
fun WorkspaceRenameContent(current: String, save: (String) -> Unit, cancel: () -> Unit, modifier: Modifier = Modifier) {
    var value by rememberSaveable(stateSaver = TextFieldValue.Saver) {
        val start = current.takeGraphemes(WorkspaceTitle.MAX_CHARACTERS)
        mutableStateOf(TextFieldValue(start, selection = TextRange(start.length)))
    }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }
    val canSave = WorkspaceTitle.canSave(value.text)
    val commit = { if (WorkspaceTitle.canSave(value.text)) save(WorkspaceTitle.cleaned(value.text)) }
    val accentText = ShellXTheme.colors.accentText
    Column(
        modifier = modifier.fillMaxWidth().imePadding().padding(horizontal = 24.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(stringResource(R.string.workspaces_rename_title), style = MaterialTheme.typography.titleLarge)
        OutlinedTextField(
            value = value,
            onValueChange = { edit ->
                val text = edit.text.takeGraphemes(WorkspaceTitle.MAX_CHARACTERS)
                value = if (text == edit.text) {
                    edit
                } else {
                    edit.copy(text = text, selection = TextRange(minOf(edit.selection.start, text.length), minOf(edit.selection.end, text.length)))
                }
            },
            modifier = Modifier.fillMaxWidth().focusRequester(focus).testTag("workspace.rename.field"),
            label = { Text(stringResource(R.string.workspaces_rename_placeholder)) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.None,
                autoCorrectEnabled = false,
                imeAction = ImeAction.Done,
            ),
            keyboardActions = KeyboardActions(onDone = { commit() }),
        )
        Row(modifier = Modifier.align(Alignment.End), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TextButton(onClick = cancel) { Text(stringResource(R.string.common_cancel), color = accentText) }
            TextButton(onClick = { commit() }, enabled = canSave, modifier = Modifier.testTag("workspace.rename.save")) {
                Text(stringResource(R.string.workspaces_rename_save), color = if (canSave) accentText else accentText.copy(alpha = 0.38f))
            }
        }
    }
}
