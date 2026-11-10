package com.shellx.app.ui.terminal

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.offset
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.unit.round
import androidx.compose.ui.window.PopupProperties
import com.shellx.app.ui.agent.AgentNotice
import com.shellx.app.ui.agent.AgentView
import kotlinx.coroutines.delay
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
import com.shellx.app.ui.components.isCompactHeight
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
 *
 * Typing (Task 13): a tap takes the keyboard; a long press also offers Paste. The key bar shows under the surface while
 * it has the keyboard ([showsKeyBar] in tests), only on the page shown and only while it takes input; when the soft
 * keyboard hides (system Back, its own key), the surface gives the focus up and the key bar goes. A paste over the
 * limit says so on the page shown only, for `AgentView.NOTICE_DURATION`. [engaged] is called when the user takes the
 * keyboard on the page shown or sends it input (a tap, the focus, typing): the workspace screen settles on its chip.
 * [holdsKeyboard] is told whether the page shown holds the keyboard (false again when it leaves): a window short in
 * height (a phone in landscape) gives it the workspace's top bar meanwhile.
 */
@Composable
fun TerminalPane(
    model: TerminalViewModel,
    terminalId: String,
    title: String,
    shown: Boolean,
    modifier: Modifier = Modifier,
    locksPaging: (Boolean) -> Unit = {},
    showsKeyBar: Boolean = false,
    engaged: () -> Unit = {},
    holdsKeyboard: (Boolean) -> Unit = {},
) {
    val state by model.state.collectAsStateWithLifecycle()
    val pageShown = shown && state.terminalId == terminalId
    Column(modifier.fillMaxSize().imePadding()) {
        if (!pageShown) {
            Box(Modifier.weight(1f).fillMaxWidth()) {
                if (state.phase == TerminalViewPhase.Unsupported) ShellPanePlaceholder() else EmptyCard()
            }
        } else {
            ShownPage(model, terminalId, title, state, showsKeyBar, locksPaging, engaged, holdsKeyboard)
        }
    }
}

object TerminalPane {
    /** What a key bar button does: a key → `model.press(key)`; ctrl → `model.toggleCtrl()`; hide keyboard → [hideKeyboard]. */
    fun perform(item: TerminalKeyBarItem, model: TerminalViewModel, hideKeyboard: () -> Unit) {
        when (item) {
            is TerminalKeyBarItem.Key -> item.key.key?.let { model.press(it) } ?: model.toggleCtrl()
            TerminalKeyBarItem.HideKeyboard -> hideKeyboard()
        }
    }
}

/** Whether a card covers the surface of the page shown: the terminal cannot be shown, or no screen came yet. */
internal fun covers(phase: TerminalViewPhase, snapshots: Int): Boolean = when (phase) {
    TerminalViewPhase.Live -> false
    TerminalViewPhase.Connecting, TerminalViewPhase.Offline -> snapshots == 0
    TerminalViewPhase.Unsupported, is TerminalViewPhase.Unavailable -> true
}

/** The page shown: composed only while it is, so whatever it holds (focus, a notice, a paging lock) goes with it. */
@Composable
private fun ColumnScope.ShownPage(
    model: TerminalViewModel,
    terminalId: String,
    title: String,
    state: TerminalViewState,
    showsKeyBar: Boolean,
    locksPaging: (Boolean) -> Unit,
    engaged: () -> Unit,
    holdsKeyboard: (Boolean) -> Unit,
) {
    // Leaving the page (a swipe, a chip, the pane gone) unlocks the pager.
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
    val ime = LocalTerminalIme.current ?: remember(context) { SystemTerminalIme(context) }
    var surface by remember { mutableStateOf<TerminalSurfaceView?>(null) }
    var focused by remember { mutableStateOf(false) }
    val keyBar = (focused || showsKeyBar) && state.acceptsInput

    // The user took the keyboard here, or sent this page input: the screen settles on its chip.
    val currentEngaged by rememberUpdatedState(engaged)
    val currentHolds by rememberUpdatedState(holdsKeyboard)
    var toldHolds by remember { mutableStateOf(false) }
    LaunchedEffect(focused) {
        if (focused) currentEngaged()
        if (focused != toldHolds) {
            toldHolds = focused
            currentHolds(focused)
        }
    }
    DisposableEffect(Unit) { onDispose { if (toldHolds) currentHolds(false) } }
    var inputsSeen by remember { mutableIntStateOf(state.sentInputs) }
    LaunchedEffect(state.sentInputs) {
        if (state.sentInputs != inputsSeen) currentEngaged()
        inputsSeen = state.sentInputs
    }

    val padding = TerminalGeometry.PADDING_DP * density.density
    var box by remember { mutableStateOf(IntSize.Zero) }
    LaunchedEffect(box) {
        if (box.width <= 0 || box.height <= 0) return@LaunchedEffect
        val grid = TerminalGeometry.phoneGrid(box.width.toFloat(), box.height.toFloat(), font.cellWidth, font.cellHeight, padding)
        model.setPhoneGrid(grid.cols, grid.rows)
    }

    // A rise of the refused-paste count, on this page only (the model is every page's).
    var notice by remember { mutableStateOf<AgentNotice?>(null) }
    var pastesSeen by remember { mutableIntStateOf(state.pasteTooLarge) }
    val tooLarge = stringResource(R.string.terminal_paste_too_large)
    LaunchedEffect(state.pasteTooLarge) {
        if (state.pasteTooLarge > pastesSeen) notice = AgentNotice(tooLarge)
        pastesSeen = state.pasteTooLarge
    }
    LaunchedEffect(notice?.id) {
        val said = notice ?: return@LaunchedEffect
        delay(AgentView.NOTICE_DURATION)
        if (notice?.id == said.id) notice = null
    }

    // The soft keyboard went down while the surface had it: the focus goes too, so the key bar hides as on the iPhone.
    // A hardware keyboard never shows the soft one, so its focus and bar stay.
    val imeUp = WindowInsets.ime.getBottom(density) > 0
    var imeWasUp by remember { mutableStateOf(false) }
    LaunchedEffect(imeUp) {
        if (imeWasUp && !imeUp && focused) surface?.clearTerminalFocus()
        imeWasUp = imeUp
    }

    val phase = state.phase
    val covered = covers(phase, state.snapshots)
    val compact = isCompactHeight()
    Box(Modifier.weight(1f).fillMaxWidth()) {
        Box(
            Modifier
                .fillMaxSize()
                // Over the key bar the card keeps less room below it, none in a short window (a phone in landscape).
                .padding(start = 12.dp, end = 12.dp, bottom = if (!keyBar) 12.dp else if (compact) 0.dp else 6.dp)
                .onSizeChanged { box = it },
        ) {
            Surface(
                model, terminalId, title, font, ime, state, covered, onLocks,
                attached = { surface = it }, onFocus = { focused = it },
            )
            if (!covered) {
                val said = notice
                if (said != null) {
                    NoticeCapsule(said.text, Modifier.align(Alignment.TopCenter).padding(start = 24.dp, end = 24.dp, top = 6.dp))
                } else if (phase == TerminalViewPhase.Offline) {
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
    if (keyBar) {
        TerminalKeyBar(state.ctrlLatched, press = { item ->
            // A tap as the page stops being the one shown never reaches the terminal shown next.
            if (model.terminalId == terminalId) TerminalPane.perform(item, model) { surface?.clearTerminalFocus() }
        })
    }
}

/** The surface host, in the card's place and shape; hidden, untouchable and silent while a card covers it. */
@Composable
private fun BoxScope.Surface(
    model: TerminalViewModel,
    terminalId: String,
    title: String,
    font: TerminalFont,
    ime: TerminalIme,
    state: TerminalViewState,
    covered: Boolean,
    onLocks: (Boolean) -> Unit,
    attached: (TerminalSurfaceView) -> Unit,
    onFocus: (Boolean) -> Unit,
) {
    val context = LocalContext.current
    var surface by remember { mutableStateOf<TerminalSurfaceView?>(null) }
    var viewport by remember { mutableStateOf<TerminalViewport?>(null) }
    var pinching by remember { mutableStateOf(false) }
    val wide = (viewport?.maxScrollX ?: 0f) > 0.5f
    LaunchedEffect(pinching || wide) { onLocks(pinching || wide) }
    val currentOnFocus by rememberUpdatedState(onFocus)

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

    // The long press's Paste, at the touch.
    var menuAt by remember { mutableStateOf<Offset?>(null) }
    var canPaste by remember { mutableStateOf(false) }

    // One modifier chain in every state, its parts switched off while covered: taking a gesture's node out of the chain
    // would take its focus target out too, and Compose then moves the focus off the surface (the keyboard with it)
    // before the surface can hide the keyboard itself.
    val semantics = Modifier.clearAndSetSemantics {
        if (!covered) {
            contentDescription = label
            // Built only when an accessibility service or a test asks; `revision` makes a new block when the screen changes.
            if (revision >= 0) text = AnnotatedString(model.screen.screenText().joinToString("\n"))
        }
    }
    val gestures = Modifier
        .pointerInput(covered) {
            if (!covered) detectPinch({ pinching = it }) { zoom, centroid -> surface?.pinch(zoom, centroid.x, centroid.y) }
        }
        .pointerInput(covered) {
            if (covered) return@pointerInput
            detectTapGestures(
                onTap = { surface?.focusAndShowKeyboard() },
                onLongPress = { at ->
                    surface?.focusAndShowKeyboard()
                    canPaste = TerminalClipboard.hasText(context)
                    menuAt = at
                },
            )
        }
        .scrollable(horizontal, Orientation.Horizontal, enabled = wide && !covered)
        .scrollable(vertical, Orientation.Vertical, enabled = !covered, flingBehavior = fling, interactionSource = drags)
    key(model, terminalId) {
        AndroidView(
            factory = { viewContext ->
                TerminalSurfaceView(viewContext, model, terminalId, font, ime).also { view ->
                    view.onViewportChange = { viewport = it }
                    view.onFocusChange = { currentOnFocus(it) }
                    surface = view
                    attached(view)
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
                view.accessibilityLabel = label
                view.render(state)
            },
            onRelease = { view ->
                view.onFocusChange = {}
                if (view.hasFocus()) view.clearTerminalFocus()
            },
        )
    }
    menuAt?.let { at ->
        Box(Modifier.offset { at.round() }) {
            DropdownMenu(
                expanded = true,
                onDismissRequest = { menuAt = null },
                // Not focusable: the terminal keeps the keyboard, as the iPhone's edit menu leaves it.
                properties = PopupProperties(focusable = false),
            ) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.terminal_paste)) },
                    enabled = canPaste,
                    onClick = {
                        menuAt = null
                        if (surface?.accepts() == true) TerminalClipboard.text(context)?.let(model::paste)
                    },
                    modifier = Modifier.testTag("terminal.paste"),
                )
            }
        }
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
