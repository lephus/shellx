package com.shellx.app

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.xmlpull.v1.XmlPullParser

/** Debug only: the network security config exists only in src/debug (ledger A-6, Spec note 17). */
@RunWith(AndroidJUnit4::class)
class DebugRelayAccessTest {
    @Test
    fun debugBuildsMayReachOnlyALoopbackRelayOverHttp() {
        val parser = ApplicationProvider.getApplicationContext<Context>().resources.getXml(R.xml.network_security_config)
        val domains = mutableListOf<String>()
        var cleartext: String? = null
        while (parser.next() != XmlPullParser.END_DOCUMENT) {
            if (parser.eventType != XmlPullParser.START_TAG) continue
            if (parser.name == "domain-config") cleartext = parser.getAttributeValue(null, "cleartextTrafficPermitted")
            if (parser.name == "domain") domains += parser.nextText()
        }
        assertEquals("true", cleartext)
        assertEquals(listOf("127.0.0.1", "localhost"), domains)
    }
}
