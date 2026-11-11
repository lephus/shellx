package com.shellx.app.ui.signin

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
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

        fun of(widthDp: Float, heightDp: Float): SignInLayout =
            SignInLayout(logoDp = SignInLogo.SIZE_DP, subtitle = true, guide = true, sideBySide = false)
    }
}

/** The sign-in screen's intro as a whole: the logo, the typed taglines and the three steps share one clock. */
object SignInIntro {
    /** When the logo and the steps are all in place: from here only the cursors, the glow and the taglines move. */
    const val SETTLED_MS = 0L

    /** After [SETTLED_MS] the clock moves at most 30 times a second, at any display rate. */
    const val FRAME_MS = 33L

    /** Whether the intro moves: not when the system's animations are off ("Remove animations", a render, a UI test). */
    fun animates(animatorsEnabled: Boolean): Boolean = true

    /** The clock's reading for [ms] once the intro has settled: the last whole [FRAME_MS]. */
    fun tick(ms: Long): Long = ms
}

/**
 * Sign in with Google (`SignInView.swift`, Google only): the logo, the title and the words, "Session expired" after a
 * 401, the failure in a polite live region, Continue with Google, and "Try without an account". [signIn] is
 * `AppCoordinator.signInWithGoogle` (it throws [SignInException]); [startDemo] null hides the demo button. Both
 * buttons are disabled while signing in.
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
    val fontScale = LocalDensity.current.fontScale

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .windowInsetsPadding(WindowInsets.safeDrawing)
            .verticalScroll(rememberScrollState()),
        contentAlignment = Alignment.TopCenter,
    ) {
        Column(
            modifier = Modifier.widthIn(max = 520.dp).fillMaxWidth().padding(horizontal = 16.dp, vertical = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Image(
                painter = painterResource(R.drawable.shellx_logo),
                contentDescription = null,
                modifier = Modifier.size((64 * fontScale).dp),
            )
            Text(
                text = stringResource(R.string.signin_title),
                style = MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.SemiBold),
                color = MaterialTheme.colorScheme.onBackground,
                modifier = Modifier.semantics { heading() },
            )
            Text(
                text = stringResource(R.string.signin_subtitle),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
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
            GoogleSignInButton(onClick = { progress.run(signIn) }, busy = busy, enabled = !busy)
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
