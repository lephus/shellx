package com.shellx.app.ui.signin

import androidx.compose.ui.autofill.contentHints
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
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

        assertEquals(KeyboardType.Number, EmailStepFields.CODE_KEYBOARD.keyboardType)
        assertEquals(ImeAction.Done, EmailStepFields.CODE_KEYBOARD.imeAction)
        assertEquals(false, EmailStepFields.CODE_KEYBOARD.autoCorrectEnabled)

        assertEquals(setOf("username", "emailAddress"), EmailStepFields.EMAIL_CONTENT.contentHints.toSet())
        assertEquals(setOf("smsOTPCode", "emailOTPCode"), EmailStepFields.CODE_CONTENT.contentHints.toSet())
    }
}
