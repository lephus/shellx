package com.shellx.app.platform

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GoogleWebClientTest {
    @Test
    fun theShippedResourceIsThePlaceholderUntilPlan1D() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val resource = context.getString(R.string.google_web_client_id)
        if (resource == GoogleWebClient.PLACEHOLDER) {
            assertNull(GoogleWebClient.id(context))
        } else {
            assertEquals(resource, GoogleWebClient.id(context))
        }
    }

    @Test
    fun onlyAWebClientIdIsReal() {
        assertTrue(GoogleWebClient.isReal("123-abc.apps.googleusercontent.com"))
        assertFalse(GoogleWebClient.isReal(GoogleWebClient.PLACEHOLDER))
        assertFalse(GoogleWebClient.isReal(""))
        assertFalse(GoogleWebClient.isReal("abc"))
    }
}
