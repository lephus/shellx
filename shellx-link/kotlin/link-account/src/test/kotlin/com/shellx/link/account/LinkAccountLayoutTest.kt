package com.shellx.link.account

import java.io.File
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class LinkAccountLayoutTest {
    @Test
    fun pairingVectorsAreReachableFromTheModuleDirectory() {
        assertTrue(File("../../spec/vectors/pairing.json").isFile)
    }
}
