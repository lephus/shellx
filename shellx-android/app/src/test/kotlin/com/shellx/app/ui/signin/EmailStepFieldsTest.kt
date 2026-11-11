package com.shellx.app.ui.signin

import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.intl.LocaleList
import com.shellx.app.testing.autofillHints
import org.junit.Assert.assertEquals
import org.junit.Test

/** What the email and code fields ask the keyboard and the autofill service for. */
class EmailStepFieldsTest {
    @Test
    fun theFieldsAskForTheRightKeyboardsAndAutofill() {
        assertEquals(KeyboardType.Email, EmailStepFields.EMAIL_KEYBOARD.keyboardType)
        assertEquals(ImeAction.Send, EmailStepFields.EMAIL_KEYBOARD.imeAction)
        assertEquals(KeyboardCapitalization.None, EmailStepFields.EMAIL_KEYBOARD.capitalization)
        assertEquals(false, EmailStepFields.EMAIL_KEYBOARD.autoCorrectEnabled)
        // An English keyboard: a Vietnamese Telex layout rewrites "ex" in "example" as "ẽ".
        assertEquals(LocaleList("en"), EmailStepFields.EMAIL_KEYBOARD.hintLocales)

        assertEquals(KeyboardType.Number, EmailStepFields.CODE_KEYBOARD.keyboardType)
        assertEquals(ImeAction.Done, EmailStepFields.CODE_KEYBOARD.imeAction)
        assertEquals(false, EmailStepFields.CODE_KEYBOARD.autoCorrectEnabled)

        assertEquals(setOf("username", "emailAddress"), autofillHints(EmailStepFields.EMAIL_CONTENT))
        assertEquals(setOf("smsOTPCode", "emailOTPCode"), autofillHints(EmailStepFields.CODE_CONTENT))
    }
}
