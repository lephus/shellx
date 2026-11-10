package com.shellx.app.ui.terminal

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.text.InputType
import android.view.KeyCharacterMap
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import com.shellx.app.R
import com.shellx.core.terminal.TerminalColors
import com.shellx.core.terminal.TerminalGeometry
import com.shellx.core.terminal.TerminalHardwareAction
import com.shellx.core.terminal.TerminalHardwareKeys
import com.shellx.core.terminal.TerminalHardwareModifiers
import com.shellx.core.terminal.TerminalViewModel
import com.shellx.core.terminal.TerminalViewPhase
import com.shellx.core.terminal.TerminalViewState
import com.shellx.core.terminal.TerminalViewport
import com.shellx.link.core.TerminalCursorShape
import com.shellx.link.core.TerminalPalette
import com.shellx.link.core.TerminalRow
import com.shellx.link.core.TerminalScreen

/**
 * Draws `model.screen` (it keeps no copy of it) through [viewport]: history rows and screen rows on the main screen,
 * screen rows on the alternate one, at `TerminalViewport.scale` (fit to the width unless pinched), following the bottom
 * unless scrolled up (then held in place by `topShift`). The iPhone's `TerminalSurfaceView` and `TerminalCanvasView` in
 * one View; the gestures are `TerminalPane`'s, so [onTouchEvent] returns false.
 *
 * A frame draws only the visible rows, from layouts kept by row object ([TerminalRowCache]): every row's backgrounds,
 * then every row's text and lines, then the cursor, then the text being composed, so a diacritic that rises into the
 * row above is never painted over.
 *
 * It is the keyboard's editor ([TerminalInputConnection]; plan 3G Design, "Soft keyboard") and takes hardware keys
 * ([handleKey]; "Hardware keys"). Input reaches the model only from the page shown and only while the model takes it
 * ([accepts]); a surface that stops accepting gives the keyboard up, and it never takes the keyboard back by itself:
 * only a tap or a long press focuses it ([focusAndShowKeyboard]).
 *
 * TalkBack reads it from this View, never from the pane's Compose node (Compose hands an AndroidView's node to its
 * View), and only while it is the terminal shown and uncovered ([readable]): [accessibilityLabel] and the rows shown,
 * built when asked; a double tap opens the keyboard, scroll actions page through the history, and a change of the
 * screen is told at most once a second. The screen is the user's: no content capture, no autofill, and on API 34+ only
 * accessibility tools read the node. Main thread only.
 */
@SuppressLint("ViewConstructor") // Made in code by TerminalPane only.
class TerminalSurfaceView(
    context: Context,
    val model: TerminalViewModel,
    /** The terminal of the page this surface belongs to: the model is every page's, and shows one terminal at a time. */
    val terminalId: String,
    val font: TerminalFont,
    private val ime: TerminalIme = SystemTerminalIme(context),
) : View(context) {
    private val density = context.resources.displayMetrics.density
    private val padding = TerminalGeometry.PADDING_DP * density
    private val cache = TerminalRowCache(font)
    private val fill = Paint()
    private val stroke = Paint().apply { style = Paint.Style.STROKE }

    /** Row layouts built so far (tests: what a frame costs). */
    internal val rowLayoutsBuilt: Int get() = cache.builds

    /** Called with every new [viewport]. */
    var onViewportChange: (TerminalViewport) -> Unit = {}

    /** What the screen is drawn with before a palette came (the card's colour). */
    var emptyColor: Int = 0

    var viewport: TerminalViewport = TerminalViewport(font.cellWidth, font.cellHeight, padding)
        private set

    private var state = TerminalViewState()
    private var lastSnapshots: Int? = null
    private var lastTopShift = 0
    private var lastSentInputs = 0

    /** What is left of a vertical drag on the alternate screen below one line (TerminalGeometry.scrollLines). */
    private var scrollCarry = 0f

    /** Called with true / false when the surface takes / gives up the focus (and with it the keyboard). */
    var onFocusChange: (Boolean) -> Unit = {}

    /** The keyboard's current connection, kept in step with the model's marked text ([render]). */
    private var connection: TerminalInputConnection? = null
    private var restartPending = false

    /** Only a tap or a long press lets the surface take the focus: nothing gives it back on its own. */
    private var mayFocus = false

    /** Key codes whose down [handleKey] took: their up is taken too. */
    private val keysDown = HashSet<Int>()

    /** A dead key's accent, waiting for the next character. */
    private var deadAccent = 0

    /** What TalkBack says first, "Terminal zsh" (VoiceOver's label); the rows shown follow it. */
    var accessibilityLabel: String = ""

    private val accessibility: AccessibilityManager? = context.getSystemService(AccessibilityManager::class.java)
    private var lastRevision = -1L

    /** When the last text change was told (uptime ms), and whether one waits for its second to pass. */
    private var lastTextChange = 0L
    private var textChangeWaits = false
    private val tellTextChange = Runnable {
        textChangeWaits = false
        sendTextChange()
    }

    init {
        // Hidden until the first render says the page is shown and uncovered.
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        // The screen is the user's: it takes no part in content capture or autofill, and only accessibility tools (not
        // every service that asks) read its node.
        importantForAutofill = IMPORTANT_FOR_AUTOFILL_NO
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) importantForContentCapture = IMPORTANT_FOR_CONTENT_CAPTURE_NO
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            setAccessibilityDataSensitive(ACCESSIBILITY_DATA_SENSITIVE_YES)
        }
        isFocusable = true
        isFocusableInTouchMode = true
    }

    // Updates

    /**
     * The model changed: a new snapshot or typing goes back to the bottom, rows added above a scrolled-up view keep it
     * in place, and a grid of other columns goes back to fit.
     */
    fun render(state: TerminalViewState) {
        this.state = state
        val screen = model.screen
        val newSnapshot = state.snapshots != lastSnapshots
        val typed = state.sentInputs != lastSentInputs
        val shift = state.topShift - lastTopShift
        lastSnapshots = state.snapshots
        lastSentInputs = state.sentInputs
        lastTopShift = state.topShift
        setViewport(viewport.contentChanged(screen.cols, shownRows(screen), if (newSnapshot) 0 else shift, toBottom = newSnapshot || typed))
        // The keyboard follows the model: a key that committed the word, a paste, another terminal shown.
        connection?.let { if (it.document != state.markedText) it.resync(state.markedText) }
        // A page that stops taking input (covered, reopening, another terminal shown) gives the keyboard up.
        if (hasFocus() && !accepts()) clearTerminalFocus()
        // Under a card, or for another terminal, TalkBack does not reach it.
        val readable = readable
        importantForAccessibility = if (readable) IMPORTANT_FOR_ACCESSIBILITY_YES else IMPORTANT_FOR_ACCESSIBILITY_NO
        if (readable && state.screenRevision != lastRevision) textChanged()
        lastRevision = state.screenRevision
        invalidate()
    }

    // Accessibility

    /** TalkBack reads this surface: its terminal is the one the model shows now, and no card covers it. */
    private val readable: Boolean
        get() {
            val now = model.state.value
            return now.terminalId == terminalId && !covers(now.phase, now.snapshots)
        }

    /**
     * The rows shown (history rows too while scrolled up), blank rows at either end left out. TalkBack speaks a node's
     * description in place of its text, so the description is the label and then these rows, as VoiceOver reads the
     * iPhone's label and value. Built only when an accessibility service asks.
     */
    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        if (!readable) return
        val rows = shownText()
        info.text = rows
        info.contentDescription = if (rows.isEmpty()) accessibilityLabel else "$accessibilityLabel\n$rows"
        if (accepts()) {
            info.isClickable = true
            info.addAction(AccessibilityAction(AccessibilityNodeInfo.ACTION_CLICK, context.getString(R.string.action_type)))
        }
        if (scrollsHistory) {
            val back = viewport.scrollY > 0.5f
            val forward = viewport.scrollY < viewport.maxScrollY - 0.5f
            if (back) info.addAction(AccessibilityAction.ACTION_SCROLL_BACKWARD)
            if (forward) info.addAction(AccessibilityAction.ACTION_SCROLL_FORWARD)
            info.isScrollable = back || forward
        }
    }

    /** A double tap opens the keyboard (as a tap does); the scroll actions page through the history. */
    override fun performAccessibilityAction(action: Int, arguments: Bundle?): Boolean {
        if (readable) {
            when (action) {
                AccessibilityNodeInfo.ACTION_CLICK -> if (accepts()) {
                    focusAndShowKeyboard()
                    return true
                }
                AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD, AccessibilityNodeInfo.ACTION_SCROLL_FORWARD -> if (scrollsHistory) {
                    val page = maxOf(viewport.height - viewport.cellHeight * viewport.scale, viewport.cellHeight * viewport.scale)
                    val before = viewport.scrollY
                    setViewport(viewport.scrolledBy(0f, if (action == AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD) -page else page))
                    if (viewport.scrollY == before) return false
                    textChanged()
                    return true
                }
            }
        }
        return super.performAccessibilityAction(action, arguments)
    }

    /** History to page through: the main screen (the alternate one's scroll goes to the Mac, by a drag). */
    private val scrollsHistory: Boolean
        get() = !model.screen.alt && viewport.maxScrollY > 0.5f

    private fun shownText(): String {
        val screen = model.screen
        val history = if (screen.alt) 0 else screen.historyRows.size
        return viewport.visibleRows.joinToString("\n") { (row(screen, it, history) ?: BLANK).text(screen.cols) }.trim('\n')
    }

    /** The text TalkBack reads changed: tell it at once, or when a second has passed since the last time. */
    private fun textChanged() {
        if (accessibility?.isEnabled != true || textChangeWaits) return
        val wait = lastTextChange + TEXT_CHANGE_INTERVAL_MS - SystemClock.uptimeMillis()
        if (lastTextChange == 0L || wait <= 0) {
            sendTextChange()
        } else {
            textChangeWaits = true
            postDelayed(tellTextChange, wait)
        }
    }

    private fun sendTextChange() {
        if (!readable || accessibility?.isEnabled != true) return
        lastTextChange = SystemClock.uptimeMillis()
        @Suppress("DEPRECATION") // AccessibilityEvent(int) is API 30.
        val event = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            AccessibilityEvent(AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED)
        } else {
            AccessibilityEvent.obtain(AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED)
        }
        event.contentChangeTypes = AccessibilityEvent.CONTENT_CHANGE_TYPE_TEXT
        sendAccessibilityEventUnchecked(event)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        removeCallbacks(tellTextChange)
        textChangeWaits = false
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        setViewport(viewport.resized(w.toFloat(), h.toFloat()))
    }

    private fun setViewport(next: TerminalViewport) {
        if (next == viewport) return
        viewport = next
        onViewportChange(next)
        invalidate()
    }

    private fun shownRows(screen: TerminalScreen): Int = (if (screen.alt) 0 else screen.historyRows.size) + screen.rows

    // Gestures (TerminalPane's)

    @SuppressLint("ClickableViewAccessibility") // The pane's gestures stand for it.
    override fun onTouchEvent(event: MotionEvent): Boolean = false

    /** The alternate screen while its grid fits the height: a vertical drag sends scroll lines to the Mac. */
    private val scrollsTheMac: Boolean
        get() = model.screen.alt && viewport.contentHeight <= viewport.height + 0.5f

    /**
     * A vertical drag of [delta] px (a finger moving down is positive): on the main screen it shows older rows and
     * returns the px used; on the alternate screen, while the grid fits the height, it becomes `model.scroll(lines)`
     * and uses all of [delta].
     */
    fun dragVertically(delta: Float): Float {
        if (scrollsTheMac) {
            val step = TerminalGeometry.scrollLines(delta, scrollCarry, font.cellHeight, viewport.scale)
            scrollCarry = step.carry
            if (step.lines != 0 && accepts()) model.scroll(step.lines)
            return delta
        }
        val before = viewport.scrollY
        setViewport(viewport.scrolledBy(0f, -delta))
        return before - viewport.scrollY
    }

    /** The drag ended: the scroll-line carry starts again at 0. */
    fun endVerticalDrag() {
        scrollCarry = 0f
    }

    /** A sideways drag pans while the grid is wider than the pane; returns the px used. */
    fun dragHorizontally(delta: Float): Float {
        val before = viewport.scrollX
        setViewport(viewport.scrolledBy(-delta, 0f))
        return before - viewport.scrollX
    }

    /** Zooms by [factor] around the point ([focusX], [focusY]) of the view, between fit and TerminalGeometry.MAX_ZOOM. */
    fun pinch(factor: Float, focusX: Float, focusY: Float) {
        setViewport(viewport.pinched(factor, focusX, focusY))
    }

    /** Input from this surface may reach the model: its page is the terminal shown, and it takes input. */
    internal fun accepts(): Boolean = model.terminalId == terminalId && model.acceptsInput

    // The keyboard

    override fun onCheckIsTextEditor(): Boolean = true

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        // A text class keeps each language's composing (Telex, VNI, CJK); no suggestions, so letters go out one by one;
        // no CAP_* or AUTO_* flag, so nothing is capitalised or rewritten; multi-line, so Enter is a key, never an action.
        outAttrs.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI or EditorInfo.IME_FLAG_NO_FULLSCREEN or
            EditorInfo.IME_FLAG_NO_ENTER_ACTION or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
        val marked = if (accepts()) model.markedText.length else 0
        outAttrs.initialSelStart = marked
        outAttrs.initialSelEnd = marked
        outAttrs.initialCapsMode = 0
        return TerminalInputConnection(
            this, model, ::accepts, ::handleKey, { TerminalClipboard.text(context) },
            report = { document, composing ->
                val end = document.length
                ime.updateSelection(this, end, end, if (composing) 0 else -1, if (composing) end else -1)
            },
            restart = ::restartKeyboard,
        ).also { connection = it }
    }

    /** The keyboard drops its composition on the next main-loop turn (once, however many asked meanwhile). */
    private fun restartKeyboard() {
        if (restartPending) return
        restartPending = true
        post {
            restartPending = false
            ime.restart(this)
        }
    }

    /** The surface asked for the keyboard and has not hidden it since (its page leaving hides it, [TerminalPane]). */
    internal var tookKeyboard: Boolean = false
        private set

    /** A tap or a long press: the surface takes the focus and the keyboard shows, while the page takes input. */
    fun focusAndShowKeyboard() {
        if (!accepts()) return
        mayFocus = true
        tookKeyboard = true
        requestFocus()
        post { ime.show(this) }
    }

    /** Hides the soft keyboard and gives up the focus. */
    fun clearTerminalFocus() {
        ime.hide(this)
        tookKeyboard = false
        mayFocus = false
        clearFocus()
    }

    override fun requestFocus(direction: Int, previouslyFocusedRect: Rect?): Boolean {
        if (!mayFocus) return false
        return super.requestFocus(direction, previouslyFocusedRect)
    }

    override fun onFocusChanged(gainFocus: Boolean, direction: Int, previouslyFocusedRect: Rect?) {
        super.onFocusChanged(gainFocus, direction, previouslyFocusedRect)
        if (!gainFocus) {
            mayFocus = false
            keysDown.clear()
            deadAccent = 0
        }
        onFocusChange(gainFocus)
    }

    // Hardware keys

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean = handleKey(event) || super.onKeyDown(keyCode, event)

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean = handleKey(event) || super.onKeyUp(keyCode, event)

    override fun onKeyMultiple(keyCode: Int, repeatCount: Int, event: KeyEvent): Boolean =
        handleKey(event) || super.onKeyMultiple(keyCode, repeatCount, event)

    /**
     * A hardware key, or a key event the keyboard sent ("Hardware keys"): downs (repeats included) go through
     * `TerminalHardwareKeys`; the up of a down it took is taken too; text of a KEYCODE_UNKNOWN multiple is typed as a key
     * (the word being composed is committed first), or pasted when it is one ([TerminalInputConnection.isPaste]).
     * A dead key waits for the next character and joins it (`KeyEvent.getDeadChar`), or is typed first when they do not
     * join. False for the system's keys (Back, volume, Meta shortcuts, function keys), and for every key while the page
     * does not take input.
     */
    fun handleKey(event: KeyEvent): Boolean {
        if (!accepts()) return false
        when (event.action) {
            KeyEvent.ACTION_UP -> return keysDown.remove(event.keyCode)
            KeyEvent.ACTION_MULTIPLE -> {
                if (event.keyCode != KeyEvent.KEYCODE_UNKNOWN) return false
                // A key's text: the word being composed is committed first; a line break or a long text is a paste (A-32).
                event.characters?.takeIf { it.isNotEmpty() }?.let {
                    if (TerminalInputConnection.isPaste(it)) model.paste(it) else model.typeKey(it)
                }
                return true
            }
            KeyEvent.ACTION_DOWN -> Unit
            else -> return false
        }
        val meta = event.metaState
        var plain = event.getUnicodeChar(meta and (KeyEvent.META_CTRL_MASK or KeyEvent.META_ALT_MASK or KeyEvent.META_META_MASK).inv())
        val chorded = event.isCtrlPressed || event.isAltPressed || event.isMetaPressed
        if (!chorded && plain and KeyCharacterMap.COMBINING_ACCENT != 0) {
            deadAccent.takeIf { it != 0 }?.let { typeCodePoint(it) }
            deadAccent = plain and KeyCharacterMap.COMBINING_ACCENT_MASK
            keysDown += event.keyCode
            return true
        }
        val accent = deadAccent
        if (accent != 0) {
            deadAccent = 0
            val joined = if (plain != 0) KeyEvent.getDeadChar(accent, plain) else 0
            if (joined != 0) plain = joined else typeCodePoint(accent)
        }
        val alt = event.getUnicodeChar(meta and (KeyEvent.META_CTRL_MASK or KeyEvent.META_META_MASK).inv())
        val modifiers = TerminalHardwareModifiers(event.isShiftPressed, event.isCtrlPressed, event.isAltPressed, event.isMetaPressed)
        when (val action = TerminalHardwareKeys.action(event.keyCode, plain, alt, modifiers)) {
            is TerminalHardwareAction.Send -> model.press(action.key, action.mods)
            is TerminalHardwareAction.Type -> model.typeKey(action.text)
            TerminalHardwareAction.DeleteBackward -> model.deleteBackward()
            TerminalHardwareAction.Paste -> TerminalClipboard.text(context)?.let(model::paste)
            TerminalHardwareAction.System -> return false
        }
        keysDown += event.keyCode
        return true
    }

    private fun typeCodePoint(codePoint: Int) {
        if (Character.isValidCodePoint(codePoint)) model.typeKey(String(Character.toChars(codePoint)))
    }

    // Drawing

    override fun onDraw(canvas: Canvas) {
        val screen = model.screen
        val palette = screen.palette
        if (palette == null || screen.cols <= 0) {
            canvas.drawColor(emptyColor)
            return
        }
        canvas.drawColor(TerminalRowLayout.argb(TerminalColors.background(palette)))
        val history = if (screen.alt) 0 else screen.historyRows.size
        val visible = viewport.visibleRows
        canvas.save()
        canvas.translate(padding - viewport.scrollX, padding - viewport.scrollY)
        val scale = viewport.scale
        canvas.scale(scale, scale)
        val drawn = ArrayList<Pair<Int, TerminalRowLayout>>(if (visible.isEmpty()) 0 else visible.last - visible.first + 1)
        for (index in visible) {
            val row = row(screen, index, history) ?: continue
            drawn += index to cache.layout(row, screen.cols, palette)
        }
        for ((index, layout) in drawn) layout.drawBackground(canvas, index * font.cellHeight)
        for ((index, layout) in drawn) layout.drawText(canvas, index * font.cellHeight, font)
        drawCursor(canvas, screen, palette, history, visible)
        drawMarkedText(canvas, screen, palette, history, visible)
        canvas.restore()
        if (!visible.isEmpty()) cache.retain(rowsAround(screen, visible, history))
    }

    /** The shown row [index]: history rows first on the main screen, then the screen's. */
    private fun row(screen: TerminalScreen, index: Int, history: Int): TerminalRow? {
        if (index < history) return screen.historyRows.getOrNull(index)
        val y = index - history
        if (y >= screen.rows) return null
        return screen.screenRows.getOrNull(y) ?: BLANK
    }

    /** The rows within [CACHE_MARGIN] of the visible ones, whose layouts stay. */
    private fun rowsAround(screen: TerminalScreen, visible: IntRange, history: Int): List<TerminalRow> {
        val first = maxOf(0, visible.first - CACHE_MARGIN)
        val last = minOf(history + screen.rows - 1, visible.last + CACHE_MARGIN)
        return (first..last).mapNotNull { row(screen, it, history) }
    }

    /**
     * The cursor's box in grid px (two columns over a wide cell), its column, and the layout of its row; none while its
     * row is out of sight (scrolled far up, its row is not among the layouts kept, and would be laid out every frame).
     */
    private fun cursorBox(screen: TerminalScreen, palette: TerminalPalette, history: Int, visible: IntRange): Triple<FloatArray, Int, TerminalRowLayout>? {
        val cursor = screen.cursor ?: return null
        if (cursor.y !in 0 until screen.rows || cursor.x !in 0 until screen.cols) return null
        val index = history + cursor.y
        if (index !in visible) return null
        val layout = cache.layout(row(screen, index, history) ?: BLANK, screen.cols, palette)
        val found = layout.cell(cursor.x)?.first
        val column = found?.column ?: cursor.x
        val width = found?.width ?: 1
        val left = column * font.cellWidth
        val top = index * font.cellHeight
        return Triple(floatArrayOf(left, top, left + width * font.cellWidth, top + font.cellHeight), column, layout)
    }

    /** Only while Live, the cursor visible and nothing composed; it never blinks. */
    private fun drawCursor(canvas: Canvas, screen: TerminalScreen, palette: TerminalPalette, history: Int, visible: IntRange) {
        val cursor = screen.cursor ?: return
        if (state.phase != TerminalViewPhase.Live || !cursor.visible || state.markedText.isNotEmpty()) return
        val (box, column, layout) = cursorBox(screen, palette, history, visible) ?: return
        val color = TerminalRowLayout.argb(TerminalColors.cursor(palette))
        val (left, top, right, bottom) = box
        fill.color = color
        when (cursor.shape) {
            TerminalCursorShape.BAR -> canvas.drawRect(left, top, left + 2 * density, bottom, fill)
            TerminalCursorShape.UNDERLINE -> canvas.drawRect(left, bottom - 2 * density, right, bottom, fill)
            TerminalCursorShape.BLOCK_HOLLOW -> {
                stroke.color = color
                stroke.strokeWidth = density
                val inset = density / 2
                canvas.drawRect(left + inset, top + inset, right - inset, bottom - inset, stroke)
            }
            else -> {
                canvas.drawRect(left, top, right, bottom, fill)
                layout.drawCellText(canvas, top, column, TerminalRowLayout.argb(TerminalColors.background(palette)), font)
            }
        }
    }

    /** The text the keyboard is composing, at the cursor's cell: palette foreground on palette background, underlined. */
    private fun drawMarkedText(canvas: Canvas, screen: TerminalScreen, palette: TerminalPalette, history: Int, visible: IntRange) {
        val marked = state.markedText
        if (marked.isEmpty()) return
        val (box, _, _) = cursorBox(screen, palette, history, visible) ?: return
        val left = box[0]
        val top = box[1]
        // Measured, not kept: every word being composed would otherwise fill the font's glyph cache.
        val paint = font.paint(bold = false, italic = false)
        paint.textScaleX = 1f
        val width = maxOf(paint.measureText(marked), font.cellWidth)
        fill.color = TerminalRowLayout.argb(TerminalColors.background(palette))
        canvas.drawRect(left, top, left + width, top + font.cellHeight, fill)
        val foreground = TerminalRowLayout.argb(TerminalColors.foreground(palette))
        paint.color = foreground
        canvas.drawText(marked, left, top + font.baseline, paint)
        // At the cell's bottom, below the font's underline position, so the dots under Vietnamese vowels (ạ, ệ) stay clear.
        fill.color = foreground
        canvas.drawRect(left, top + font.cellHeight - density, left + width, top + font.cellHeight, fill)
    }

    private companion object {
        /** Rows kept laid out beyond the visible ones, above and below. */
        const val CACHE_MARGIN = 40

        /** At most one screen change told to TalkBack a second. */
        const val TEXT_CHANGE_INTERVAL_MS = 1_000L

        val BLANK = TerminalRow()
    }
}
