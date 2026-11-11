package com.shellx.app.ui.signin

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.contentType
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shellx.app.R
import com.shellx.app.ui.components.PrimaryButton
import com.shellx.app.ui.components.Spinner
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.ui.theme.StatusTone
import com.shellx.app.ui.theme.color
import com.shellx.core.account.EmailSignInModel
import com.shellx.core.account.EmailSignInState
import com.shellx.core.account.SignInException

/** What the email steps call (the model's methods on the sign-in screen); the defaults do nothing (renders). */
class EmailStepCalls(
    val start: () -> Unit = {},
    val setEmail: (String) -> Unit = {},
    val send: () -> Unit = {},
    val setCode: (String) -> Unit = {},
    val verify: () -> Unit = {},
    val resend: () -> Unit = {},
    val changeEmail: () -> Unit = {},
)

/** What the two fields ask of the keyboard and of the autofill service. */
object EmailStepFields {
    val EMAIL_KEYBOARD = KeyboardOptions(
        capitalization = KeyboardCapitalization.None,
        autoCorrectEnabled = false,
        keyboardType = KeyboardType.Email,
        imeAction = ImeAction.Send,
    )

    val CODE_KEYBOARD = KeyboardOptions(autoCorrectEnabled = false, keyboardType = KeyboardType.Number, imeAction = ImeAction.Done)

    /** A password manager offers the account's address. */
    val EMAIL_CONTENT: ContentType = ContentType.Username + ContentType.EmailAddress

    /**
     * Best effort: Android has no hint for a code that came by email, and reads none out of a mail; an autofill service
     * that knows one of these two may still offer it. Paste is the path that must work.
     */
    val CODE_CONTENT: ContentType = ContentType.SmsOtpCode + ContentType("emailOTPCode")
}

/**
 * A field's own text: what was typed shows at once, in the same frame, whatever the screen's state does meanwhile (a
 * field fed straight from a StateFlow drops fast keystrokes). When the state behind the field moves on and its text is
 * not what the field shows (the model emptied the code, or took the relay's spelling of the address), the field takes
 * the state's text, with the cursor at its end. Never saved with the screen: the code must not reach the saved state,
 * and the address comes back from the model.
 */
private class FieldText(handed: String, revision: Any?) {
    var value by mutableStateOf(at(handed))
    private var lastRevision = revision

    /**
     * [handed] is the state's text and [revision] the state it came with. Only a new [revision] is looked at: the same
     * one handed in again says nothing new, and what was typed since stays.
     */
    fun follow(handed: String, revision: Any?) {
        if (revision == lastRevision) return
        lastRevision = revision
        if (handed != value.text) value = at(handed)
    }

    /**
     * Shows [typed] put through [clean] and returns the cleaned text when it differs from what the field showed (a
     * moved cursor reports nothing).
     */
    fun type(typed: TextFieldValue, clean: (String) -> String): String? {
        val text = clean(typed.text)
        val changed = text != value.text
        value = if (text == typed.text) typed else at(text)
        return text.takeIf { changed }
    }

    private companion object {
        fun at(text: String) = TextFieldValue(text, TextRange(text.length))
    }
}

/** The failure of an email step, under its field: its words in the error tone, read out when it appears. */
@Composable
private fun StepFailure(error: SignInException?, tag: String) {
    val message = error?.let(SignInErrorText::message) ?: return
    Text(
        text = stringResource(message),
        style = MaterialTheme.typography.bodyMedium,
        color = StatusTone.ERROR.color(),
        modifier = Modifier.testTag(tag).semantics { liveRegion = LiveRegionMode.Polite },
    )
}

/** The words of a primary button, or while it [waits] a spinner in their place, the words still its name for TalkBack. */
@Composable
private fun WaitingButton(
    label: String,
    waits: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    PrimaryButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.fillMaxWidth().then(if (waits) Modifier.semantics { contentDescription = label } else Modifier),
    ) {
        if (waits) Spinner(Modifier.size(20.dp)) else Text(label)
    }
}

/**
 * The email step (IDLE, EMAIL, SENDING: the sign-in screen's first screen), 12 dp between its rows: the address field,
 * a failure under it, and Send code (a spinner while the relay is asked). [enabled] false turns the field and Send code
 * off (Google signs in). With [autoFocus] the field takes the focus once, when the step appears: a tap outside can
 * still put the keyboard down.
 */
@Composable
internal fun EmailStep(
    state: EmailSignInState,
    calls: EmailStepCalls,
    autoFocus: Boolean,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val sending = state.step == EmailSignInState.Step.SENDING
    val field = remember { FieldText(state.email, state) }
    field.follow(state.email, state)
    val focus = remember { FocusRequester() }
    if (autoFocus) LaunchedEffect(Unit) { focus.requestFocus() }

    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        OutlinedTextField(
            value = field.value,
            onValueChange = { typed -> field.type(typed) { it.take(EmailSignInModel.MAX_EMAIL_LENGTH) }?.let(calls.setEmail) },
            modifier = Modifier
                .fillMaxWidth()
                .focusRequester(focus)
                .testTag("signin.email.field")
                .semantics { contentType = EmailStepFields.EMAIL_CONTENT },
            enabled = enabled && (state.step == EmailSignInState.Step.EMAIL || state.step == EmailSignInState.Step.IDLE),
            label = { Text(stringResource(R.string.signin_email_field)) },
            singleLine = true,
            keyboardOptions = EmailStepFields.EMAIL_KEYBOARD,
            keyboardActions = KeyboardActions(onSend = { if (enabled) calls.send() }),
        )
        StepFailure(state.error, "signin.email.error")
        WaitingButton(
            label = stringResource(R.string.signin_email_send),
            waits = sending,
            enabled = enabled && state.canSend,
            onClick = calls.send,
            modifier = Modifier.testTag("signin.email.send"),
        )
    }
}

/**
 * The code step (CODE, VERIFYING, DONE), 12 dp between its rows: where the code went, the six-digit field, a failure
 * under it, Verify (a spinner while the relay checks), Resend code with its countdown, and "Use a different email". A
 * dead code turns the field and Verify off; Resend is then open at once.
 */
@Composable
internal fun CodeStep(state: EmailSignInState, calls: EmailStepCalls, autoFocus: Boolean, modifier: Modifier = Modifier) {
    val inCode = state.step == EmailSignInState.Step.CODE
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            text = stringResource(R.string.signin_email_sent_to, state.email),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.fillMaxWidth().testTag("signin.email.sentTo").semantics { liveRegion = LiveRegionMode.Polite },
        )
        EmailCodeField(
            code = state.code,
            onCode = calls.setCode,
            label = stringResource(R.string.signin_email_code),
            enabled = inCode && !state.codeDead,
            onDone = calls.verify,
            modifier = Modifier.fillMaxWidth().testTag("signin.email.code"),
            autoFocus = autoFocus,
            revision = state,
        )
        StepFailure(state.error, "signin.email.error")
        WaitingButton(
            label = stringResource(R.string.signin_email_verify),
            waits = !inCode,
            enabled = state.canVerify,
            onClick = calls.verify,
            modifier = Modifier.testTag("signin.email.verify"),
        )
        ResendCodeButton(state, calls.resend, Modifier.fillMaxWidth().testTag("signin.email.resend"))
        val canChange = inCode && !state.resending
        TextButton(
            onClick = calls.changeEmail,
            enabled = canChange,
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("signin.email.change"),
        ) {
            Text(stringResource(R.string.signin_email_change), color = if (canChange) ShellXTheme.colors.accentText else LocalContentColor.current)
        }
    }
}

/**
 * The six-digit field (sign-in and Delete Account): one field, so a paste and an autofill land whole and TalkBack reads
 * one. It shows digits only, at most six of them, whatever is typed or pasted ("123 456", a whole sentence). [onDone] is
 * the keyboard's Done, which also puts the keyboard down. The test tag comes with [modifier].
 *
 * The field shows what is typed at once and reports it with [onCode]. It takes [code] back when [revision] changes and
 * [code] is not what it shows: hand in the state [code] comes from, so that a code the model emptied in the same frame
 * it was typed in (a wrong code refused at once) empties the field too. By default [revision] is [code] itself.
 */
@Composable
fun EmailCodeField(
    code: String,
    onCode: (String) -> Unit,
    label: String,
    enabled: Boolean,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
    autoFocus: Boolean = false,
    revision: Any? = code,
) {
    val field = remember { FieldText(code, revision) }
    field.follow(code, revision)
    val focus = remember { FocusRequester() }
    if (autoFocus) LaunchedEffect(Unit) { focus.requestFocus() }

    OutlinedTextField(
        value = field.value,
        onValueChange = { typed -> field.type(typed, EmailSignInModel::digits)?.let(onCode) },
        modifier = modifier.focusRequester(focus).semantics { contentType = EmailStepFields.CODE_CONTENT },
        enabled = enabled,
        label = { Text(label) },
        textStyle = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Monospace, letterSpacing = 4.sp),
        singleLine = true,
        keyboardOptions = EmailStepFields.CODE_KEYBOARD,
        keyboardActions = KeyboardActions(
            onDone = {
                onDone()
                // And the keyboard goes down, as Done does on any field.
                defaultKeyboardAction(ImeAction.Done)
            },
        ),
    )
}

/**
 * "Resend code", or "Resend code in N s" while the relay's wait runs; on when the state allows a resend. The test tag
 * comes with [modifier].
 */
@Composable
fun ResendCodeButton(state: EmailSignInState, onResend: () -> Unit, modifier: Modifier = Modifier) {
    val enabled = state.canResend
    TextButton(onClick = onResend, enabled = enabled, modifier = modifier.heightIn(min = 48.dp)) {
        Text(
            text = if (state.resendInSeconds > 0) {
                stringResource(R.string.signin_email_resend_in, state.resendInSeconds)
            } else {
                stringResource(R.string.signin_email_resend)
            },
            color = if (enabled) ShellXTheme.colors.accentText else LocalContentColor.current,
        )
    }
}
