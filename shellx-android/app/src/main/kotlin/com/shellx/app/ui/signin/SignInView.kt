package com.shellx.app.ui.signin

import android.animation.ValueAnimator
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.withInfiniteAnimationFrameMillis
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
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
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.flowWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.shellx.app.R
import com.shellx.app.platform.AndroidClock
import com.shellx.app.ui.theme.AppLanguage
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.ui.theme.StatusTone
import com.shellx.app.ui.theme.color
import com.shellx.core.account.EmailCodeActions
import com.shellx.core.account.EmailSignInModel
import com.shellx.core.account.EmailSignInState
import com.shellx.core.account.SignInException
import com.shellx.core.platform.Clock
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
 * What the sign-in screen shows in a window [of] a given size (the room inside the system bars, in dp, without the
 * keyboard): the logo's side, whether the subtitle and the three steps have room, whether the logo and the words stand
 * beside the email field and the buttons (a phone in landscape, a tablet) or above them, and whether the taglines are
 * typed under the title (not while the intro is folded: the keyboard is up, an address is typed, or the code step
 * shows).
 */
data class SignInLayout(
    val logoDp: Int,
    val subtitle: Boolean,
    val guide: Boolean,
    val sideBySide: Boolean,
    val tagline: Boolean = true,
) {
    companion object {
        // Measured on the first screen at font scale 1.0, English and Vietnamese (SignInFitTest): one column needs
        // 747 dp with the subtitle and the steps (758 on a 360 dp wide phone), 690 dp with the steps (702), 546 dp
        // without them, 522 dp with the small logo; two columns need 462 dp beside the steps (on a 700 dp wide
        // window), 306 dp without them. Each threshold leaves a few dp to spare. What gives way first: the subtitle,
        // then the steps, then the big logo; never a button, the field, the "or" line or the demo link.

        /** Under this height, and in landscape, the logo is the small one. */
        const val COMPACT_HEIGHT_DP = 560

        /** Two columns: from this height the subtitle shows under the taglines; under it the taglines stand in for it. */
        const val SUBTITLE_MIN_HEIGHT_DP = 700

        /** One column, where the field and the buttons stand under the words: the same, from here. */
        const val COLUMN_SUBTITLE_MIN_HEIGHT_DP = 760

        /** Two columns: under this height (a phone in landscape) the three steps are left out. */
        const val GUIDE_MIN_HEIGHT_DP = 470

        /** One column: under this height the three steps leave their room to the field and the buttons. */
        const val COLUMN_GUIDE_MIN_HEIGHT_DP = 705

        /** A landscape window at least this wide has two columns; a narrower one (a split screen) keeps one. */
        const val SIDE_BY_SIDE_MIN_WIDTH_DP = 600

        /**
         * [folded]: the intro folds (the keyboard is up, an address is typed, or the code step shows): the small logo
         * and the title only, no taglines, no subtitle, no steps; one or two columns as without it, so the keyboard
         * never moves the field to another column.
         */
        fun of(widthDp: Float, heightDp: Float, folded: Boolean = false): SignInLayout {
            val landscape = widthDp > heightDp
            val sideBySide = landscape && widthDp >= SIDE_BY_SIDE_MIN_WIDTH_DP
            if (folded) {
                return SignInLayout(SignInLogo.COMPACT_SIZE_DP, subtitle = false, guide = false, sideBySide = sideBySide, tagline = false)
            }
            return SignInLayout(
                logoDp = if (landscape || heightDp < COMPACT_HEIGHT_DP) SignInLogo.COMPACT_SIZE_DP else SignInLogo.SIZE_DP,
                subtitle = heightDp >= if (sideBySide) SUBTITLE_MIN_HEIGHT_DP else COLUMN_SUBTITLE_MIN_HEIGHT_DP,
                guide = heightDp >= if (sideBySide) GUIDE_MIN_HEIGHT_DP else COLUMN_GUIDE_MIN_HEIGHT_DP,
                sideBySide = sideBySide,
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
 * Sign in (`SignInView.swift`, with an emailed code or with Google): the animated logo, the title, the typed taglines
 * and the three steps ([SignInContent]); under them the email field with Send code, "or", Continue with Google and "Try
 * without an account"; "Session expired" after a 401 and Google's failure in a polite live region above them. [signIn]
 * is `AppCoordinator.signInWithGoogle` (it throws [SignInException]); [startDemo] null hides the demo button. The
 * buttons are disabled while signing in.
 *
 * The first screen is the email step ([EmailSignInModel] over [email], the coordinator's two calls; [clock] counts
 * "Resend code" down): Send code opens the code step in this same screen, in place of the field and the buttons. The
 * system's Back goes from the code step back to the first screen, and does nothing while a request is on the relay.
 * The steps survive a rotation in a ViewModel, and a killed process through [emailRestore]: the screen reads it once,
 * when its steps are first made, and writes into it what the step it shows needs to come back (never the typed code).
 */
@Composable
fun SignInView(
    expired: Boolean,
    signIn: suspend () -> Unit,
    startDemo: (() -> Unit)?,
    modifier: Modifier = Modifier,
    initialError: SignInException? = null,
    email: EmailCodeActions = EmailCodeActions.Unavailable,
    clock: Clock = AndroidClock,
    emailRestore: MutableState<EmailSignInModel.Saved?> = remember { mutableStateOf(null) },
) {
    val progress: SignInProgress = viewModel { SignInProgress(initialError) }
    val busy by progress.busy.collectAsStateWithLifecycle()
    val error by progress.error.collectAsStateWithLifecycle()

    val holder: EmailSignInHolder = viewModel { EmailSignInHolder(email, clock, emailRestore.value) }
    val model = holder.model
    val emailState by model.state.collectAsStateWithLifecycle()
    // The relay writes the mail in the app's language.
    val locale = AppLanguage.current().language
    val emailCalls = remember(model, locale) {
        EmailStepCalls(
            start = { model.start() },
            setEmail = { text ->
                // The holder starts the steps on the email step; this only makes sure.
                model.start()
                model.setEmail(text)
            },
            send = { model.send(locale) },
            setCode = model::setCode,
            verify = model::verify,
            resend = { model.resend(locale) },
            changeEmail = model::changeEmail,
        )
    }
    // Only while the screen is the one shown: a screen that fades out behind the signed-in app writes nothing more.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(holder, lifecycle) {
        // An empty first screen leaves nothing to come back to.
        model.state.flowWithLifecycle(lifecycle).collect {
            emailRestore.value = model.saved()?.takeUnless { it.challengeId == null && it.email.isEmpty() }
        }
    }
    // The first screen is the email step: there Back leaves the app, as on any first screen.
    BackHandler(enabled = emailState.step in BACK_STEPS) { model.back() }

    SignInContent(
        expired = expired,
        error = error,
        busy = busy,
        continueWithGoogle = { progress.run(signIn) },
        startDemo = startDemo,
        introMs = rememberSignInIntroClock(),
        modifier = modifier,
        email = emailState,
        emailCalls = emailCalls,
        autoFocus = true,
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

/** Where the system's Back goes a step back (or waits for the relay): the code step, and a request under way. */
private val BACK_STEPS = setOf(EmailSignInState.Step.SENDING, EmailSignInState.Step.CODE, EmailSignInState.Step.VERIFYING)

/**
 * The sign-in screen as it is at [introMs] (milliseconds since it appeared; null: no motion, everything in place).
 *
 * The first screen ([email] at IDLE, EMAIL or SENDING): in portrait the logo, the title, the taglines and the steps
 * stand in the middle of the room above the email field, and the field with Send code, "or", Continue with Google and
 * the demo link at the bottom; in a landscape window wide enough they stand beside them ([SignInLayout]). The screen
 * scrolls when a window is too short for it (large text, a long failure). The field and the buttons are there and take
 * taps from the first frame: only the logo, the taglines and the steps follow the clock. No field takes the focus on
 * arrival: the keyboard comes up when the field is tapped.
 *
 * The intro folds ([SignInLayout.of]'s `folded`) while [keyboardUp], while an address is typed, and in the code step:
 * the small logo and the title stand at the top with the field (or the code step) under them, beside them in two
 * columns; no taglines, no subtitle, no steps. The keyboard going down with an empty field brings the whole intro back.
 * The field stays the same field through the fold, so it keeps the focus. The intro's clock runs on (the logo's cursor
 * and glow). "Session expired" and Google's failure show on the first screen only; an email failure shows under its
 * field. With [autoFocus] the code step's field takes the focus when the step appears, and the email field when the
 * screen comes back from the code step.
 *
 * The room is the window's inside the system bars and the display cutout, measured without the keyboard: one or two
 * columns never change while the keyboard moves (on a foldable a switch would drop the field's focus). The keyboard
 * takes its room from the scrolling container, which keeps the focused field in view.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun SignInContent(
    expired: Boolean,
    error: SignInException?,
    busy: Boolean,
    continueWithGoogle: () -> Unit,
    startDemo: (() -> Unit)?,
    introMs: (() -> Long)?,
    modifier: Modifier = Modifier,
    email: EmailSignInState = EmailSignInState(EmailSignInState.Step.EMAIL),
    emailCalls: EmailStepCalls = EmailStepCalls(),
    autoFocus: Boolean = false,
    keyboardUp: Boolean = WindowInsets.isImeVisible,
) {
    // The steps are in place when the intro has settled: they read a clock that stops there, and rest after it.
    val settling = remember(introMs) { introMs?.let { derivedStateOf { minOf(it(), SignInIntro.SETTLED_MS) } } }
    val reveal: (Int) -> Float = remember(settling) { { row -> SignInGuide.reveal(row, settling?.value) } }
    val firstScreen = email.step in FIRST_SCREEN_STEPS
    val folded = !firstScreen || keyboardUp || email.email.isNotEmpty()
    // The email field takes the focus only on the way back from the code step, never when the screen appears.
    var cameBack by remember { mutableStateOf(false) }
    LaunchedEffect(firstScreen) { if (!firstScreen) cameBack = true }
    val step: @Composable (Modifier) -> Unit = { stepModifier ->
        if (firstScreen) {
            FirstStep(expired, error, busy, continueWithGoogle, startDemo, email, emailCalls, autoFocus && cameBack, stepModifier)
        } else {
            CodeStep(email, emailCalls, autoFocus, stepModifier)
        }
    }

    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .windowInsetsPadding(WindowInsets.systemBars.union(WindowInsets.displayCutout)),
    ) {
        val layout = SignInLayout.of(maxWidth.value, maxHeight.value, folded)
        // The window's height: the content is at least as tall, so it can stand in the middle or at the bottom.
        val room = if (constraints.hasBoundedHeight) maxHeight else 0.dp
        if (layout.sideBySide) {
            Box(
                modifier = Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()),
                contentAlignment = if (folded) Alignment.TopCenter else Alignment.Center,
            ) {
                Row(
                    modifier = Modifier
                        .widthIn(max = 960.dp)
                        .fillMaxWidth()
                        .then(if (folded) Modifier else Modifier.heightIn(min = room))
                        .padding(horizontal = 24.dp, vertical = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(32.dp),
                    verticalAlignment = if (folded) Alignment.Top else Alignment.CenterVertically,
                ) {
                    Hero(layout, introMs, Modifier.weight(1f))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                        if (layout.guide) SignInGuide(reveal)
                        step(Modifier)
                    }
                }
            }
        } else {
            Column(
                modifier = Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Column(
                    modifier = Modifier
                        .widthIn(max = 520.dp)
                        .fillMaxWidth()
                        .then(if (folded) Modifier else Modifier.heightIn(min = room))
                        .padding(horizontal = 16.dp, vertical = 24.dp),
                    // Folded: top-aligned, where the keyboard never reaches the field. Whole: the room left over is
                    // shared above and below the words (an empty first row), and the field and the buttons stand at
                    // the bottom.
                    verticalArrangement = if (folded) Arrangement.Top else Arrangement.SpaceBetween,
                ) {
                    if (!folded) Spacer(Modifier.fillMaxWidth())
                    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                        Hero(layout, introMs)
                        if (layout.guide) SignInGuide(reveal)
                    }
                    step(Modifier.padding(top = 24.dp))
                }
            }
        }
    }
}

/** The steps the first screen stands for: the email step, before and while its code is asked for. */
private val FIRST_SCREEN_STEPS = setOf(EmailSignInState.Step.IDLE, EmailSignInState.Step.EMAIL, EmailSignInState.Step.SENDING)

/**
 * The logo, the title and, while the intro is whole, the typed taglines and (in a tall window) the subtitle: centred.
 * Folded, it keeps the logo and the title ([SignInLayout.tagline]).
 */
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
        if (layout.tagline) {
            Spacer(Modifier.height(8.dp))
            TypedTagline(
                lines = listOf(
                    stringResource(R.string.signin_tagline_1),
                    stringResource(R.string.signin_tagline_2),
                    stringResource(R.string.signin_tagline_3),
                ),
                introMs = introMs,
            )
        }
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
 * The first screen's controls: "Session expired" and Google's failure, then in a column 12 dp apart the email field
 * with its failure and Send code ([EmailStep]), "or", Continue with Google, and "Try without an account". While Google
 * signs in everything is off and Google's button waits; while a code is asked for, the field, Google and the demo link
 * are off and Send code waits.
 */
@Composable
private fun FirstStep(
    expired: Boolean,
    error: SignInException?,
    busy: Boolean,
    continueWithGoogle: () -> Unit,
    startDemo: (() -> Unit)?,
    email: EmailSignInState,
    calls: EmailStepCalls,
    autoFocus: Boolean,
    modifier: Modifier = Modifier,
) {
    val sending = email.step == EmailSignInState.Step.SENDING
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
            EmailStep(email, calls, autoFocus, enabled = !busy)
            OrDivider()
            GoogleSignInButton(onClick = continueWithGoogle, busy = busy, enabled = !busy && !sending)
            if (startDemo != null) {
                val on = !busy && !sending
                TextButton(
                    onClick = startDemo,
                    enabled = on,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("signin.demo"),
                ) {
                    Text(stringResource(R.string.signin_demo), color = if (on) ShellXTheme.colors.accentText else LocalContentColor.current)
                }
            }
        }
    }
}
