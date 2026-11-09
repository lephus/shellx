package com.shellx.app.ui.composer

import android.content.ActivityNotFoundException
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.composer.AttachmentPick
import com.shellx.core.composer.AttachmentReadException
import com.shellx.core.composer.OutgoingAttachment
import com.shellx.core.composer.PendingPicks
import com.shellx.core.platform.CoreLog
import com.shellx.link.core.AttachmentKind
import com.shellx.link.core.ShellXLink
import kotlinx.coroutines.Dispatchers

/**
 * The composer's "+" (`AttachMenu.swift`): a menu of Photos (the Photo Picker, 5 at a time) and Files (the document
 * picker, several at once). What is picked is read in the order picked through [picks] (the composer holds Send until
 * none is left, and each one's ✕ cancels it) and added with [onAdd], up to `ShellXLink.MAX_ATTACHMENTS_PER_MESSAGE`.
 * What cannot be added says why through [note], which a new pick clears.
 */
@Composable
fun AttachMenu(
    attachments: List<OutgoingAttachment>,
    onAdd: (OutgoingAttachment) -> Unit,
    picks: PendingPicks,
    side: Dp,
    enabled: Boolean,
    note: (String?) -> Unit,
) {
    val context = LocalContext.current
    val res = context.resources
    val reader = LocalAttachmentReader.current ?: remember(context) { AttachmentPreparer(context.contentResolver, Dispatchers.IO) }
    val loading by picks.ids.collectAsState()
    val current by rememberUpdatedState(attachments)
    val add by rememberUpdatedState(onAdd)
    val say by rememberUpdatedState(note)
    var expanded by remember { mutableStateOf(false) }

    // A pick still being read holds its place.
    val room = (ShellXLink.MAX_ATTACHMENTS_PER_MESSAGE - attachments.size - loading.size).coerceAtLeast(0)
    val active = enabled && room > 0

    fun received(result: Result<OutgoingAttachment>) {
        result.fold(
            onSuccess = { attachment ->
                if (current.size >= ShellXLink.MAX_ATTACHMENTS_PER_MESSAGE) {
                    say(res.getString(R.string.composer_attach_too_many))
                } else {
                    add(attachment)
                }
            },
            onFailure = { error ->
                say((error as? AttachmentReadException)?.let { AttachmentPreparer.message(it, res) } ?: res.getString(R.string.composer_attach_pick_failed))
            },
        )
    }

    fun read(uris: List<Uri>, kind: AttachmentKind) {
        if (uris.isEmpty()) return
        // Named when its read starts, after what the composer holds then, so photos read in a row get distinct names.
        picks.read(uris.map { uri -> suspend { reader.read(AttachmentPick(uri.toString(), kind), current.map { it.name }) } }, ::received)
    }

    val photos = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(PHOTO_PICKER_MAX)) { read(it, AttachmentKind.IMAGE) }
    val files = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { read(it, AttachmentKind.FILE) }

    fun launching(launch: () -> Unit) {
        expanded = false
        say(null)
        try {
            launch()
        } catch (e: ActivityNotFoundException) {
            CoreLog.log("attach_pick_failed ${e.javaClass.simpleName}")
            say(res.getString(R.string.composer_attach_pick_failed))
        }
    }

    val label = stringResource(R.string.composer_attach)
    Box {
        Box(
            Modifier
                .size(side)
                .alpha(if (active) 1f else 0.4f)
                .background(MaterialTheme.colorScheme.surfaceContainerHigh, CircleShape)
                .clickable(enabled = active, role = Role.Button) { expanded = true }
                .semantics { contentDescription = label }
                .testTag("composer.attach"),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Add, contentDescription = null, tint = ShellXTheme.colors.accentText)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.composer_attach_photos)) },
                leadingIcon = { Icon(Icons.Outlined.PhotoLibrary, contentDescription = null) },
                onClick = { launching { photos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) } },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.composer_attach_files)) },
                leadingIcon = { Icon(Icons.Outlined.Description, contentDescription = null) },
                onClick = { launching { files.launch(arrayOf("*/*")) } },
            )
        }
    }
}

/** The Photo Picker takes a fixed limit; picks beyond the room left get "Up to 5 attachments" (Spec note). */
private const val PHOTO_PICKER_MAX = 5
