package com.shellx.app.ui.pairing

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ClipboardManager
import android.content.Intent
import android.content.res.Resources
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.Devices
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material.icons.outlined.VideocamOff
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.shellx.app.R
import com.shellx.app.platform.CameraAccess
import com.shellx.app.ui.components.PrimaryButton
import com.shellx.app.ui.components.shellXCard
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.ui.theme.StatusTone
import com.shellx.app.ui.theme.color
import com.shellx.core.pairing.PairingFailure
import com.shellx.core.pairing.PairingModel
import com.shellx.core.pairing.PairingScanFilter
import kotlinx.coroutines.launch

/** What the pairing page's controls run (`PairingSheetContent.Actions`). */
class PairingActions(
    val scanned: (String) -> Unit = {},
    val paste: () -> Unit = {},
    val confirm: () -> Unit = {},
    /** Back to scanning after a failure. */
    val retry: () -> Unit = {},
    /** Leaves the page (and so cancels whatever is under way). */
    val close: () -> Unit = {},
    val openSettings: () -> Unit = {},
)

/** What the pairing page says (`PairingSheetContent.message` and `announcement`). */
object PairingText {
    fun message(failure: PairingFailure, res: Resources): String = when (failure) {
        PairingFailure.NotShellXCode -> res.getString(R.string.pairing_error_not_shell_x_code)
        PairingFailure.NeedsUpdate -> res.getString(R.string.pairing_error_needs_update)
        PairingFailure.DamagedCode -> res.getString(R.string.pairing_error_damaged_code)
        PairingFailure.Denied -> res.getString(R.string.pairing_error_denied)
        PairingFailure.Expired -> res.getString(R.string.pairing_error_expired)
        PairingFailure.OtherAccount -> res.getString(R.string.pairing_error_other_account)
        PairingFailure.Network -> res.getString(R.string.pairing_error_network)
        is PairingFailure.Server -> res.getString(R.string.pairing_error_server, failure.code)
    }

    /** What TalkBack hears when the page moves to [step] (the step title is a polite live region). */
    fun announcement(step: PairingModel.Step, res: Resources): String? = when (step) {
        PairingModel.Step.Idle, is PairingModel.Step.Confirm -> null
        is PairingModel.Step.WaitingForMac -> res.getString(R.string.pairing_waiting, step.machineName)
        is PairingModel.Step.Paired -> res.getString(R.string.pairing_paired, step.machineName)
        is PairingModel.Step.Failed -> message(step.failure, res)
    }
}

/**
 * Cancels the pairing when its back stack entry is popped (onCleared), never on recomposition or a configuration
 * change: the entry's ViewModel outlives a recreated page.
 */
class PairingRouteViewModel(cancel: () -> Unit) : ViewModel() {
    /** The latest page's cancel (a recreated page hands over its own). */
    internal var cancel: () -> Unit = cancel

    override fun onCleared() {
        cancel()
    }
}

/** Put in the `pairing` destination: leaving the page (Back, Close, a new root) cancels the attempt; rotating, a
 *  dark-mode switch or a language change does not (Review Focus 1). */
@Composable
fun CancelPairingWhenLeft(cancel: () -> Unit) {
    val route = viewModel { PairingRouteViewModel(cancel) }
    SideEffect { route.cancel = cancel }
}

/**
 * The "Pair a Mac" page (`PairingSheet.swift`, route `pairing`): scan the Mac's QR code (or paste its code), confirm
 * the Mac's name, wait for Allow on the Mac, done. The camera is asked for when the scanner is about to show, never
 * before; a refused camera offers Settings.
 */
@Composable
fun PairingScreen(model: PairingModel, close: () -> Unit) {
    val context = LocalContext.current
    val step by model.step.collectAsStateWithLifecycle()
    var camera by rememberSaveable { mutableStateOf(CameraAccess.current(context)) }
    // A request on its way survives a recreated page, so a rotation never asks twice.
    var asking by rememberSaveable { mutableStateOf(false) }
    val request = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        camera = if (granted) CameraAccess.AUTHORIZED else CameraAccess.DENIED
        asking = false
    }
    val idle = step == PairingModel.Step.Idle
    LaunchedEffect(idle, camera) {
        if (idle && camera == CameraAccess.NOT_DETERMINED && !asking) {
            asking = true
            request.launch(Manifest.permission.CAMERA)
        }
    }
    // Back from Settings with the camera allowed (or taken away). A refusal stands until the camera is allowed.
    LifecycleResumeEffect(Unit) {
        val now = CameraAccess.current(context)
        camera = if (camera == CameraAccess.DENIED && now != CameraAccess.AUTHORIZED) CameraAccess.DENIED else now
        onPauseOrDispose {}
    }
    val scope = rememberCoroutineScope()
    val clipboard = remember(context) { context.getSystemService(ClipboardManager::class.java) }
    val actions = remember(model, close) {
        PairingActions(
            scanned = { model.begin(it) },
            paste = { model.begin(PairingPaste.take(clipboard, context)) },
            // 3C runs the attempt in the hub's scope; this only waits for it.
            confirm = { scope.launch { model.confirm() } },
            retry = { model.cancel() },
            close = close,
            openSettings = {
                val settings = Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", context.packageName, null),
                )
                try {
                    context.startActivity(settings)
                } catch (_: ActivityNotFoundException) {
                    // No settings screen to open: the paste path still works.
                }
            },
        )
    }
    PairingScreenContent(step, camera, actions)
}

/**
 * What the pairing page shows for one [step]; no model, so render tests can show every step. [scanner] is the camera
 * view (a black box in renders); [spinner] draws the waiting spinner in `LocalContentColor` (a still one in renders,
 * which never hold an endless animation).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PairingScreenContent(
    step: PairingModel.Step,
    camera: CameraAccess,
    actions: PairingActions = PairingActions(),
    modifier: Modifier = Modifier,
    scanner: @Composable (Modifier, (String) -> Unit) -> Unit = { m, onCode -> QrScanner(onCode, m) },
    spinner: @Composable (Modifier) -> Unit = { CircularProgressIndicator(it, color = LocalContentColor.current) },
) {
    val background = MaterialTheme.colorScheme.background
    Scaffold(
        modifier = modifier,
        containerColor = background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.pairing_title)) },
                navigationIcon = {
                    IconButton(onClick = actions.close, modifier = Modifier.testTag("pairing.close")) {
                        Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.common_close))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = background),
            )
        },
    ) { padding ->
        Box(
            modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()),
            contentAlignment = Alignment.TopCenter,
        ) {
            Column(Modifier.widthIn(max = 520.dp).fillMaxWidth().padding(horizontal = 20.dp, vertical = 16.dp)) {
                StepContent(step, camera, actions, scanner, spinner)
            }
        }
    }
}

@Composable
private fun StepContent(
    step: PairingModel.Step,
    camera: CameraAccess,
    actions: PairingActions,
    scanner: @Composable (Modifier, (String) -> Unit) -> Unit,
    spinner: @Composable (Modifier) -> Unit,
) {
    val res = LocalContext.current.resources
    val accentText = ShellXTheme.colors.accentText
    when (step) {
        PairingModel.Step.Idle -> ScanStep(camera, actions, scanner, spinner)
        is PairingModel.Step.Confirm -> Message(
            icon = Icons.Outlined.Devices,
            tint = accentText,
            title = stringResource(R.string.pairing_confirm_title, step.machineName),
            detail = stringResource(R.string.pairing_confirm_message),
            live = false,
        ) {
            PrimaryButton(onClick = actions.confirm, modifier = Modifier.fillMaxWidth().testTag("pairing.confirm")) {
                Text(stringResource(R.string.pairing_confirm_button), style = MaterialTheme.typography.titleMedium)
            }
            TextButton(
                onClick = actions.close,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("pairing.cancel"),
            ) { Text(stringResource(R.string.common_cancel), color = accentText) }
        }
        is PairingModel.Step.WaitingForMac -> Message(
            icon = null,
            tint = accentText,
            title = stringResource(R.string.pairing_waiting, step.machineName),
            detail = stringResource(R.string.pairing_waiting_detail),
            live = true,
            spinner = spinner,
        ) {
            OutlinedButton(
                onClick = actions.close,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("pairing.cancel"),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = accentText),
            ) { Text(stringResource(R.string.common_cancel)) }
        }
        is PairingModel.Step.Paired -> Message(
            icon = Icons.Filled.CheckCircle,
            tint = StatusTone.DONE.color(),
            title = stringResource(R.string.pairing_paired, step.machineName),
            detail = null,
            live = true,
        ) {
            PrimaryButton(onClick = actions.close, modifier = Modifier.fillMaxWidth().testTag("pairing.done")) {
                Text(stringResource(R.string.pairing_done), style = MaterialTheme.typography.titleMedium)
            }
        }
        is PairingModel.Step.Failed -> Message(
            icon = Icons.Filled.Warning,
            tint = StatusTone.ERROR.color(),
            title = PairingText.message(step.failure, res),
            detail = null,
            live = true,
        ) {
            PrimaryButton(onClick = actions.retry, modifier = Modifier.fillMaxWidth().testTag("pairing.retry")) {
                Text(stringResource(R.string.pairing_retry), style = MaterialTheme.typography.titleMedium)
            }
        }
    }
}

/** The first step: the camera (or why there is none), the instructions, and the paste fallback. */
@Composable
private fun ScanStep(
    camera: CameraAccess,
    actions: PairingActions,
    scanner: @Composable (Modifier, (String) -> Unit) -> Unit,
    spinner: @Composable (Modifier) -> Unit,
) {
    // Fresh each time the scanner shows, so the code that was just cancelled can be scanned again.
    val filter = remember { PairingScanFilter() }
    var sawOtherCode by rememberSaveable { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    val onCode: (String) -> Unit = { payload ->
        when (val verdict = filter.accept(payload)) {
            is PairingScanFilter.Verdict.Pairing -> {
                haptics.performHapticFeedback(HapticFeedbackType.Confirm)
                actions.scanned(verdict.text)
            }
            PairingScanFilter.Verdict.NotShellX -> sawOtherCode = true
            PairingScanFilter.Verdict.Ignored -> Unit
        }
    }
    val accentText = ShellXTheme.colors.accentText
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        when (camera) {
            CameraAccess.AUTHORIZED, CameraAccess.NOT_DETERMINED -> {
                Viewfinder(camera == CameraAccess.AUTHORIZED, onCode, scanner, spinner)
                if (sawOtherCode) {
                    val tint = StatusTone.NEEDS_YOU.color()
                    Row(
                        modifier = Modifier.semantics(mergeDescendants = true) {}.testTag("pairing.otherCode"),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Filled.QrCode, contentDescription = null, tint = tint)
                        Text(
                            stringResource(R.string.pairing_error_not_shell_x_code),
                            style = MaterialTheme.typography.bodyMedium,
                            color = tint,
                        )
                    }
                }
            }
            CameraAccess.DENIED -> {
                Notice(Icons.Outlined.VideocamOff, stringResource(R.string.pairing_camera_denied))
                PrimaryButton(onClick = actions.openSettings, modifier = Modifier.fillMaxWidth().testTag("pairing.openSettings")) {
                    Text(stringResource(R.string.pairing_camera_open_settings), style = MaterialTheme.typography.titleMedium)
                }
            }
            CameraAccess.UNAVAILABLE -> Notice(Icons.Outlined.PhotoCamera, stringResource(R.string.pairing_camera_unavailable))
        }
        Text(
            stringResource(R.string.pairing_instructions),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        OutlinedButton(
            onClick = actions.paste,
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("pairing.paste"),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = accentText),
        ) {
            Icon(Icons.Outlined.ContentPaste, contentDescription = null)
            Spacer(Modifier.width(8.dp))
            Text(stringResource(R.string.pairing_paste))
        }
    }
}

/** A black square (at most 360 dp) holding the camera view, or a spinner until the camera is allowed, with a white
 *  frame inset 48 dp. TalkBack reads it as one element. */
@Composable
private fun Viewfinder(
    authorized: Boolean,
    onCode: (String) -> Unit,
    scanner: @Composable (Modifier, (String) -> Unit) -> Unit,
    spinner: @Composable (Modifier) -> Unit,
) {
    val label = stringResource(R.string.pairing_camera_label)
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Box(
            modifier = Modifier
                .widthIn(max = 360.dp)
                .fillMaxWidth()
                .aspectRatio(1f)
                .clip(RoundedCornerShape(16.dp))
                .background(Color.Black)
                .testTag("pairing.scanner")
                .clearAndSetSemantics { contentDescription = label },
            contentAlignment = Alignment.Center,
        ) {
            if (authorized) {
                scanner(Modifier.fillMaxSize(), onCode)
            } else {
                CompositionLocalProvider(LocalContentColor provides Color.White) { spinner(Modifier) }
            }
            Box(
                Modifier.fillMaxSize().padding(48.dp)
                    .border(3.dp, Color.White.copy(alpha = 0.85f), RoundedCornerShape(12.dp)),
            )
        }
    }
}

/** Why there is no scanner: a card with a symbol and the words, read as one. */
@Composable
private fun Notice(icon: ImageVector, text: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .shellXCard(RoundedCornerShape(12.dp))
            .padding(16.dp)
            .semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(text, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurface)
    }
}

/** A centred step: a symbol (or the spinner), a title (a heading, and a polite live region when [live]), an
 *  optional detail, then the buttons. */
@Composable
private fun Message(
    icon: ImageVector?,
    tint: Color,
    title: String,
    detail: String?,
    live: Boolean,
    spinner: (@Composable (Modifier) -> Unit)? = null,
    buttons: @Composable ColumnScope.() -> Unit,
) {
    val symbolSize = (56 * LocalDensity.current.fontScale).dp
    Column(
        modifier = Modifier.fillMaxWidth().padding(top = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(Modifier.heightIn(min = symbolSize).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
            if (spinner != null) {
                CompositionLocalProvider(LocalContentColor provides tint) { spinner(Modifier.size(48.dp)) }
            } else if (icon != null) {
                Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(symbolSize))
            }
        }
        Text(
            text = title,
            style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.SemiBold),
            color = MaterialTheme.colorScheme.onBackground,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .semantics {
                    heading()
                    if (live) liveRegion = LiveRegionMode.Polite
                }
                .testTag("pairing.message"),
        )
        if (detail != null) {
            Text(
                text = detail,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        Column(Modifier.fillMaxWidth().padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { buttons() }
    }
}
