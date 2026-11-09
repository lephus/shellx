package com.shellx.core.pairing

import com.shellx.core.pairing.PairingScanFilter.Verdict
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PairingScanFilterTest {
    private val code = "shellx-link://pair?v=1&m=m1&s=s1&k=k&c=c&n=Mac"

    @Test fun shellXCodeAccepted() {
        val filter = PairingScanFilter()
        assertEquals(Verdict.Pairing(code), filter.accept(code))
        // Any shellx-link code goes on to the parser, which tells a damaged one apart.
        assertEquals(Verdict.Pairing("SHELLX-LINK://pair?v=9"), filter.accept("SHELLX-LINK://pair?v=9"))
        assertEquals(Verdict.Pairing(code), filter.accept(" $code\n"), "blanks around the code are dropped")
    }

    @Test fun otherCodesReportedAndScanningContinues() {
        val filter = PairingScanFilter()
        assertEquals(Verdict.NotShellX, filter.accept("https://shellx.pro"))
        assertEquals(Verdict.NotShellX, filter.accept("WIFI:S:home;T:WPA;P:secret;;"))
        assertEquals(Verdict.Pairing(code), filter.accept(code), "a ShellX code after other codes still pairs")
    }

    @Test fun sameCodeIgnoredUntilAnotherSeen() {
        val filter = PairingScanFilter()
        assertEquals(Verdict.NotShellX, filter.accept("https://shellx.pro"))
        // The camera reports a code in view many times a second.
        assertEquals(Verdict.Ignored, filter.accept("https://shellx.pro"))
        assertEquals(Verdict.Pairing(code), filter.accept(code))
        assertEquals(Verdict.Ignored, filter.accept(code))
        assertEquals(Verdict.NotShellX, filter.accept("https://shellx.pro"))
    }

    @Test fun isPairingText() {
        assertTrue(PairingScanFilter.isPairingText(code))
        assertTrue(PairingScanFilter.isPairingText("\n$code "))
        assertFalse(PairingScanFilter.isPairingText(""))
        assertFalse(PairingScanFilter.isPairingText("shellx-linkpair"))
        assertFalse(PairingScanFilter.isPairingText("see shellx-link://pair?v=1"))
    }

    /** A QR code with the scheme in capitals still pairs: the filter passes it on and PairingModel lowercases the
     *  scheme before parsing. */
    @Test fun uppercaseSchemeIsAPairingCode() {
        val filter = PairingScanFilter()
        assertEquals(Verdict.Pairing("SHELLX-LINK://PAIR"), filter.accept("SHELLX-LINK://PAIR"))
    }
}
