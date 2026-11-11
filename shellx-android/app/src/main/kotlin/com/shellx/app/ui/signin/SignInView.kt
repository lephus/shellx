package com.shellx.app.ui.signin

import android.animation.ValueAnimator
import androidx.compose.animation.core.withInfiniteAnimationFrameMillis
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.shellx.app.R
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.ui.theme.StatusTone
import com.shellx.app.ui.theme.color
import com.shellx.core.account.SignInException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * The sign-in screen's progress (carry 3D-3): a ViewModel, so a rotation or a theme or language change keeps the
 * spinner and the error. One sign-in at a time; the coordinator runs it detached, so a screen that went away never
 * leaves it half done, and a later tap joins it.
 */
class SignInProgress(initialError: SignInException?) : ViewModel() {
    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy.asStateFlow()

    private val _error = MutableStateFlow(initialError)

    /** The last failure; Cancelled is kept as null (closing Google's sheet shows nothing). */
    val error: StateFlow<SignInException?> = _error.asStateFlow()

    /** A tap while busy does nothing. */
    fun run(signIn: suspend () -> Unit) {
        if (_busy.value) return
        _busy.value = true
        _error.value = null
        viewModelScope.launch {
            try {
                signIn()
            } catch (e: SignInException) {
                _error.value = e.takeIf { SignInErrorText.message(it) != null }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _error.value = SignInException.Server("unknown")
            } finally {
                _busy.value = false
            }
        }
    }
}

/**
 * What the sign-in screen shows in a window [of] a given size (the room inside the system bars, in dp): the logo's
 * side, whether the subtitle and the three steps have room, and whether the logo and the words stand beside the
 * buttons (a phone in landscape, a tablet) or above them.
 */
data class SignInLayout(val logoDp: Int, val subtitle: Boolean, val guide: Boolean, val sideBySide: Boolean) {
    companion object {
        /** Under this height, and in landscape, the logo is the small one. */
        const val COMPACT_HEIGHT_DP = 600

        /** From this height the subtitle shows under the taglines; under it the taglines stand in for it. */
        const val SUBTITLE_MIN_HEIGHT_DP = 700

        /** Under this height (a phone in landscape) the three steps are left out. */
        const val GUIDE_MIN_HEIGHT_DP = 400

        /** A landscape window at least this wide has two columns; a narrower one (a split screen) keeps one. */
        const val SIDE_BY_SIDE_MIN_WIDTH_DP = 600

        fun of(widthDp: Float, heightDp: Float): SignInLayout {
            val landscape = widthDp > heightDp
            return SignInLayout(
                logoDp = if (landscape || heightDp < COMPACT_HEIGHT_DP) SignInLogo.COMPACT_SIZE_DP else SignInLogo.SIZE_DP,
                subtitle = heightDp >= SUBTITLE_MIN_HEIGHT_DP,
                guide = heightDp >= GUIDE_MIN_HEIGHT_DP,
                sideBySide = landscape && widthDp >= SIDE_BY_SIDE_MIN_WIDTH_DP,
            )
        }
    }
}

/** The sign-in screen's intro as a whole: the logo, the typed taglines and the three steps share one clock. */
object SignInIntro {
    /** When the logo and the steps are all in place: from here only the cursors, the glow and the taglines move. */
    val SETTLED_MS: Long = maxOf(SignInLogo.INTRO_MS, SignInGuide.END_MS)

    /** After [SETTLED_MS] the clock moves at most 30 times a second, at any display rate. */
    const val FRAME_MS = 33L

    /** Whether the intro moves: not when the system's animations are off ("Remove animations", a render, a UI test). */
    fun animates(animatorsEnabled: Boolean): Boolean = animatorsEnabled

    /** The clock's reading for [ms] once the intro has settled: the last whole [FRAME_MS]. */
    fun tick(ms: Long): Long = ms / FRAME_MS * FRAME_MS
}

/**
 * Sign in with Google (`SignInView.swift`, Google only): the animated logo, the title, the typed taglines and the
 * three steps ([SignInContent]), "Session expired" after a 401, the failure in a polite live region, Continue with
 * Google, and "Try without an account". [signIn] is `AppCoordinator.signInWithGoogle` (it throws [SignInException]);
 * [startDemo] null hides the demo button. Both buttons are disabled while signing in.
 */
@Composable
fun SignInView(
    expired: Boolean,
    signIn: suspend () -> Unit,
    startDemo: (() -> Unit)?,
    modifier: Modifier = Modifier,
    initialError: SignInException? = null,
) {
    val progress: SignInProgress = viewModel { SignInProgress(initialError) }
    val busy by progress.busy.collectAsStateWithLifecycle()
    val error by progress.error.collectAsStateWithLifecycle()

    SignInContent(
        expired = expired,
        error = error,
        busy = busy,
        continueWithGoogle = { progress.run(signIn) },
        startDemo = startDemo,
        introMs = rememberSignInIntroClock(),
        modifier = modifier,
    )
}

/**
 * The intro's clock: the milliseconds since the screen appeared, read anew each frame until the intro has settled
 * and at most 30 times a second after it. Null while the system's animations are off: nothing moves then. The clock
 * stops with the screen (its effect leaves with it, and frames stop while the app is in the background), and a
 * rotation or a theme change carries it on where it was instead of playing the intro again.
 */
@Composable
internal fun rememberSignInIntroClock(): (() -> Long)? {
    var motion by remember { mutableStateOf(SignInIntro.animates(ValueAnimator.areAnimatorsEnabled())) }
    // "Remove animations" may have changed while the app was away.
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        motion = SignInIntro.animates(ValueAnimator.areAnimatorsEnabled())
    }
    if (!motion) return null

    val elapsed = rememberSaveable(saver = Saver({ it.longValue }, { mutableLongStateOf(it) })) { mutableLongStateOf(0L) }
    LaunchedEffect(elapsed) {
        val start = withFrameMillis { it } - elapsed.longValue
        while (elapsed.longValue < SignInIntro.SETTLED_MS) {
            withFrameMillis { elapsed.longValue = it - start }
        }
        // What goes on for ever (the cursors, the glow, the taglines) is an infinite animation: a UI test that waits
        // for the screen to be idle ends it here, with the logo and the steps in place.
        while (true) {
            withInfiniteAnimationFrameMillis { elapsed.longValue = maxOf(elapsed.longValue, SignInIntro.tick(it - start)) }
        }
    }
    return remember(elapsed) { { elapsed.longValue } }
}

/**
 * The sign-in screen as it is at [introMs] (milliseconds since it appeared; null: no motion, everything in place).
 * In portrait the logo, the title, the taglines and the steps stand in the middle of the room above the buttons, and
 * the buttons at the bottom; in a landscape window wide enough they stand beside the buttons ([SignInLayout]). The
 * screen scrolls when a window is too short for it (large text, a long failure). The buttons are there and take taps
 * from the first frame: only the logo, the taglines and the steps follow the clock.
 */
@Composable
internal fun SignInContent(
    expired: Boolean,
    error: SignInException?,
    busy: Boolean,
    continueWithGoogle: () -> Unit,
    startDemo: (() -> Unit)?,
    introMs: (() -> Long)?,
    modifier: Modifier = Modifier,
) {
    // The steps are in place when the intro has settled: they read a clock that stops there, and rest after it.
    val settling = remember(introMs) { introMs?.let { derivedStateOf { minOf(it(), SignInIntro.SETTLED_MS) } } }
    val reveal: (Int) -> Float = remember(settling) { { row -> SignInGuide.reveal(row, settling?.value) } }

    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .windowInsetsPadding(WindowInsets.safeDrawing),
    ) {
        val layout = SignInLayout.of(maxWidth.value, maxHeight.value)
        // The window's height: the content is at least as tall, so it can stand in the middle or at the bottom.
        val room = if (constraints.hasBoundedHeight) maxHeight else 0.dp
        if (layout.sideBySide) {
            Box(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), contentAlignment = Alignment.Center) {
                Row(
                    modifier = Modifier
                        .widthIn(max = 960.dp)
                        .fillMaxWidth()
                        .heightIn(min = room)
                        .padding(horizontal = 24.dp, vertical = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(32.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Hero(layout, introMs, Modifier.weight(1f))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                        if (layout.guide) SignInGuide(reveal)
                        Actions(expired, error, busy, continueWithGoogle, startDemo)
                    }
                }
            }
        } else {
            Column(
                modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Column(
                    modifier = Modifier
                        .widthIn(max = 520.dp)
                        .fillMaxWidth()
                        .heightIn(min = room)
                        .padding(horizontal = 16.dp, vertical = 24.dp),
                    verticalArrangement = Arrangement.SpaceBetween,
                ) {
                    // An empty first row: the room left over is then shared above and below the words, and the
                    // buttons stand at the bottom.
                    Spacer(Modifier.fillMaxWidth())
                    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                        Hero(layout, introMs)
                        if (layout.guide) SignInGuide(reveal)
                    }
                    Actions(expired, error, busy, continueWithGoogle, startDemo, Modifier.padding(top = 24.dp))
                }
            }
        }
    }
}

/** The logo, the title, the typed taglines and, in a tall window, the subtitle: centred. */
@Composable
private fun Hero(layout: SignInLayout, introMs: (() -> Long)?, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        SignInLogo(
            size = layout.logoDp.dp,
            pose = { if (introMs != null) SignInLogo.pose(introMs()) else SignInLogo.REST },
        )
        Spacer(Modifier.height(16.dp))
        Text(
            text = stringResource(R.string.signin_title),
            style = MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.SemiBold),
            color = MaterialTheme.colorScheme.onBackground,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().testTag("signin.title").semantics { heading() },
        )
        Spacer(Modifier.height(8.dp))
        TypedTagline(
            lines = listOf(
                stringResource(R.string.signin_tagline_1),
                stringResource(R.string.signin_tagline_2),
                stringResource(R.string.signin_tagline_3),
            ),
            introMs = introMs,
        )
        if (layout.subtitle) {
            Spacer(Modifier.height(8.dp))
            Text(
                text = stringResource(R.string.signin_subtitle),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().testTag("signin.subtitle"),
            )
        }
    }
}

/**
 * "Session expired", the failure, and under them the buttons in a column 12 dp apart: Continue with Google, then
 * "Try without an account". Another way to sign in is one more row in that column.
 */
@Composable
private fun Actions(
    expired: Boolean,
    error: SignInException?,
    busy: Boolean,
    continueWithGoogle: () -> Unit,
    startDemo: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        if (expired) {
            Text(
                text = stringResource(R.string.signin_expired),
                style = MaterialTheme.typography.bodyMedium,
                color = StatusTone.NEEDS_YOU.color(),
                modifier = Modifier.testTag("signin.expired"),
            )
        }
        error?.let(SignInErrorText::message)?.let { message ->
            Text(
                text = stringResource(message),
                style = MaterialTheme.typography.bodyMedium,
                color = StatusTone.ERROR.color(),
                modifier = Modifier.testTag("signin.error").semantics { liveRegion = LiveRegionMode.Polite },
            )
        }
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            GoogleSignInButton(onClick = continueWithGoogle, busy = busy, enabled = !busy)
            if (startDemo != null) {
                TextButton(
                    onClick = startDemo,
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("signin.demo"),
                ) {
                    Text(stringResource(R.string.signin_demo), color = ShellXTheme.colors.accentText)
                }
            }
        }
    }
}
