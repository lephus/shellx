package com.shellx.app.ui.terminal

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.gestures.FlingBehavior
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.ScrollScope
import androidx.compose.foundation.gestures.ScrollableDefaults
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.rememberScrollableState
import androidx.compose.foundation.gestures.scrollable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CancelPresentation
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.text
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.shellx.app.R
import com.shellx.app.ui.components.SecondaryButton
import com.shellx.app.ui.components.Spinner
import com.shellx.app.ui.workspaces.NoticeCapsule
import com.shellx.app.ui.workspaces.ShellPanePlaceholder
import com.shellx.core.terminal.TerminalGeometry
import com.shellx.core.terminal.TerminalUnavailableReason
import com.shellx.core.terminal.TerminalViewModel
import com.shellx.core.terminal.TerminalViewPhase
import com.shellx.core.terminal.TerminalViewState
import com.shellx.core.terminal.TerminalViewport

private val CARD_SHAPE = RoundedCornerShape(14.dp)

/**
 * A shell chip's page, and an agent chip's shown as its terminal (`TerminalPane.swift`). [shown] is the page the pager
 * settled on (3E's `PaneContent`); the page shown is the one that is [shown] and whose [terminalId] the model shows.
 *
 * The page shown draws the terminal ([TerminalSurfaceView]), or says why it cannot: the Mac's ShellX shows no terminals
 * ([ShellPanePlaceholder]), the terminal is gone, refused or failed (with Try Again), it is opening, or the Mac is
 * offline before any screen came. Once a screen came it stays: dimmed under a line while the Mac is offline, with a
 * small spinner while it reopens. Any other page (a neighbour while swiping) is a plain card. The page shown keeps the
 * surface under those cards too, and its content box reports the phone grid in every state, because the size is what
 * the open asks for.
 *
 * The pane never runs the model: the screen that owns it runs it once (`WorkspaceView`), so two pages of one screen
 * never compete for its pushes; a swipe shows another terminal, whose page starts from its own open and snapshot. Of two
 * screens of one Mac that run at once, the newer collection takes the pushes (plan 3G chunk B).
 *
 * Gestures (plan 3G, "Renderer"): a vertical drag scrolls the history on the main screen, or sends scroll lines on the
 * alternate screen while the grid fits the height (no fling there); a horizontal drag pans while the grid is wider
 * than the pane; two fingers pinch between fit and 2. While a pinch is under way or the grid is wider than the pane,
 * [locksPaging] is told true, and false again when that ends or the page stops being shown or leaves.
 */
@Composable
fun TerminalPane(
    model: TerminalViewModel,
    terminalId: String,
    title: String,
    shown: Boolean,
    modifier: Modifier = Modifier,
    locksPaging: (Boolean) -> Unit = {},
) {
    val state by model.state.collectAsStateWithLifecycle()
    val pageShown = shown && state.terminalId == terminalId
    Column(modifier.fillMaxSize().imePadding()) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (!pageShown) {
                if (state.phase == TerminalViewPhase.Unsupported) ShellPanePlaceholder() else EmptyCard()
            } else {
                ShownPage(model, terminalId, title, state, locksPaging)
            }
        }
    }
}

/** Whether a card covers the surface of the page shown: the terminal cannot be shown, or no screen came yet. */
internal fun covers(phase: TerminalViewPhase, snapshots: Int): Boolean = when (phase) {
    TerminalViewPhase.Live -> false
    TerminalViewPhase.Connecting, TerminalViewPhase.Offline -> snapshots == 0
    TerminalViewPhase.Unsupported, is TerminalViewPhase.Unavailable -> true
}

@Composable
private fun ShownPage(model: TerminalViewModel, terminalId: String, title: String, state: TerminalViewState, locksPaging: (Boolean) -> Unit) {
    // Composed only while the page is the one shown: leaving it (a swipe, a chip, the pane gone) unlocks the pager.
    val currentLocks by rememberUpdatedState(locksPaging)
    var told by remember { mutableStateOf(false) }
    val onLocks = { now: Boolean ->
        if (now != told) {
            told = now
            currentLocks(now)
        }
    }
    DisposableEffect(Unit) { onDispose { if (told) currentLocks(false) } }
    val context = LocalContext.current
    val density = LocalDensity.current
    val font = remember(context, density.density) { TerminalFont(context) }
    val padding = TerminalGeometry.PADDING_DP * density.density
    var box by remember { mutableStateOf(IntSize.Zero) }
    LaunchedEffect(box) {
        if (box.width <= 0 || box.height <= 0) return@LaunchedEffect
        val grid = TerminalGeometry.phoneGrid(box.width.toFloat(), box.height.toFloat(), font.cellWidth, font.cellHeight, padding)
        model.setPhoneGrid(grid.cols, grid.rows)
    }
    val phase = state.phase
    val covered = covers(phase, state.snapshots)
    Box(
        Modifier
            .fillMaxSize()
            .padding(start = 12.dp, end = 12.dp, bottom = 12.dp)
            .onSizeChanged { box = it },
    ) {
        Surface(model, terminalId, title, font, state, covered, onLocks)
        if (!covered) {
            if (phase == TerminalViewPhase.Offline) {
                Box(Modifier.align(Alignment.TopCenter).padding(start = 24.dp, end = 24.dp, top = 6.dp).testTag("terminal.offline")) {
                    NoticeCapsule(stringResource(R.string.terminal_offline))
                }
            }
            if (phase == TerminalViewPhase.Connecting) {
                val connecting = stringResource(R.string.terminal_connecting)
                Spinner(
                    Modifier
                        .align(Alignment.TopEnd)
                        .padding(18.dp)
                        .size(16.dp)
                        .semantics { contentDescription = connecting },
                )
            }
        }
    }
    if (covered) Cover(phase, retry = model::retry)
}

/** The surface host, in the card's place and shape; hidden, untouchable and silent while a card covers it. */
@Composable
private fun Surface(
    model: TerminalViewModel,
    terminalId: String,
    title: String,
    font: TerminalFont,
    state: TerminalViewState,
    covered: Boolean,
    onLocks: (Boolean) -> Unit,
) {
    var surface by remember { mutableStateOf<TerminalSurfaceView?>(null) }
    var viewport by remember { mutableStateOf<TerminalViewport?>(null) }
    var pinching by remember { mutableStateOf(false) }
    val wide = (viewport?.maxScrollX ?: 0f) > 0.5f
    LaunchedEffect(pinching || wide) { onLocks(pinching || wide) }

    val emptyColor = MaterialTheme.colorScheme.surfaceContainer.toArgb()
    val label = stringResource(R.string.terminal_surface_label, title)
    val revision = state.screenRevision
    val alt = model.screen.alt
    val vertical = rememberScrollableState { delta -> surface?.dragVertically(delta) ?: 0f }
    val horizontal = rememberScrollableState { delta -> surface?.dragHorizontally(delta) ?: 0f }
    val drags = remember { MutableInteractionSource() }
    LaunchedEffect(drags) {
        drags.interactions.collect { if (it is DragInteraction.Stop || it is DragInteraction.Cancel) surface?.endVerticalDrag() }
    }
    val fling = if (alt) NoFling else ScrollableDefaults.flingBehavior()

    val semantics = if (covered) {
        Modifier.clearAndSetSemantics {}
    } else {
        Modifier.semantics {
            contentDescription = label
            // Built only when an accessibility service or a test asks; `revision` makes a new block when the screen changes.
            if (revision >= 0) text = AnnotatedString(model.screen.screenText().joinToString("\n"))
        }
    }
    val gestures = if (covered) {
        Modifier
    } else {
        Modifier
            .pointerInput(Unit) { detectPinch({ pinching = it }) { zoom, centroid -> surface?.pinch(zoom, centroid.x, centroid.y) } }
            .scrollable(horizontal, Orientation.Horizontal, enabled = wide)
            .scrollable(vertical, Orientation.Vertical, flingBehavior = fling, interactionSource = drags)
    }
    key(model, terminalId) {
        AndroidView(
            factory = { context ->
                TerminalSurfaceView(context, model, terminalId, font).also { view ->
                    view.onViewportChange = { viewport = it }
                    surface = view
                }
            },
            modifier = Modifier
                .fillMaxSize()
                .clip(CARD_SHAPE)
                .border(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.1f), CARD_SHAPE)
                .alpha(
                    when {
                        covered -> 0f
                        state.phase == TerminalViewPhase.Offline -> 0.5f
                        else -> 1f
                    },
                )
                .testTag("terminal.surface")
                .then(semantics)
                .then(gestures),
            update = { view ->
                view.emptyColor = emptyColor
                view.render(state)
            },
        )
    }
}

/** No fling on the alternate screen: its drags are scroll lines sent to the Mac. */
private object NoFling : FlingBehavior {
    override suspend fun ScrollScope.performFling(initialVelocity: Float): Float = 0f
}

/**
 * Two or more fingers: each move's zoom around its centroid, and those changes consumed in the Initial pass, so neither
 * the pager nor the drags see a pinch. [pinching] says when one starts and ends.
 */
private suspend fun androidx.compose.ui.input.pointer.PointerInputScope.detectPinch(
    pinching: (Boolean) -> Unit,
    zoomed: (Float, Offset) -> Unit,
) {
    awaitEachGesture {
        awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
        var active = false
        try {
            while (true) {
                val event = awaitPointerEvent(PointerEventPass.Initial)
                val pressed = event.changes.count { it.pressed }
                if (pressed == 0) break
                if (pressed >= 2) {
                    if (!active) {
                        active = true
                        pinching(true)
                    }
                    val zoom = event.calculateZoom()
                    val centroid = event.calculateCentroid(useCurrent = true)
                    if (zoom != 1f && centroid != Offset.Unspecified) zoomed(zoom, centroid)
                    event.changes.forEach { if (it.positionChanged()) it.consume() }
                } else if (active) {
                    // One finger left: the rest of the gesture is no drag either.
                    event.changes.forEach { if (it.positionChanged()) it.consume() }
                }
            }
        } finally {
            if (active) pinching(false)
        }
    }
}

/** The card over the surface ([covers]). */
@Composable
private fun Cover(phase: TerminalViewPhase, retry: () -> Unit) {
    when (phase) {
        TerminalViewPhase.Unsupported -> ShellPanePlaceholder()
        is TerminalViewPhase.Unavailable -> when (phase.reason) {
            TerminalUnavailableReason.GONE ->
                Message("terminal.unavailable", Icons.Filled.CancelPresentation, stringResource(R.string.terminal_gone))
            TerminalUnavailableReason.REFUSED ->
                Message("terminal.unavailable", Icons.Filled.Lock, stringResource(R.string.workspaces_alert_refused_control))
            TerminalUnavailableReason.FAILED ->
                Message("terminal.unavailable", Icons.Filled.Warning, stringResource(R.string.terminal_failed)) {
                    SecondaryButton(onClick = retry, modifier = Modifier.testTag("terminal.retry")) {
                        Text(stringResource(R.string.terminal_retry))
                    }
                }
        }
        TerminalViewPhase.Offline -> Message("terminal.offline", Icons.Filled.WifiOff, stringResource(R.string.workspaces_alert_offline))
        TerminalViewPhase.Connecting, TerminalViewPhase.Live -> Connecting()
    }
}

@Composable
private fun Connecting() {
    Card(Modifier.semantics(mergeDescendants = true) {}.testTag("terminal.connecting")) {
        Spinner(Modifier.size(32.dp), strokeWidth = 3.dp)
        Text(
            stringResource(R.string.terminal_connecting),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

/** A message page: [icon] over [text] (read as one), then [action]. */
@Composable
private fun Message(tag: String, icon: ImageVector, text: String, action: @Composable () -> Unit = {}) {
    Card(Modifier.testTag(tag)) {
        Column(
            Modifier.semantics(mergeDescendants = true) {},
            verticalArrangement = Arrangement.spacedBy(10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(40.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                text,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        action()
    }
}

/** A page card in [ShellPanePlaceholder]'s place, shape and colours. */
@Composable
private fun Card(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier
            .fillMaxSize()
            .padding(start = 12.dp, end = 12.dp, bottom = 12.dp)
            .background(MaterialTheme.colorScheme.surfaceContainer, CARD_SHAPE)
            .border(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.1f), CARD_SHAPE)
            .padding(24.dp)
            .then(modifier),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
        content = content,
    )
}

/** A page that is not the one shown: the card, empty. */
@Composable
private fun EmptyCard() {
    Box(
        Modifier
            .fillMaxSize()
            .padding(start = 12.dp, end = 12.dp, bottom = 12.dp)
            .background(MaterialTheme.colorScheme.surfaceContainer, CARD_SHAPE)
            .border(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.1f), CARD_SHAPE),
    )
}
