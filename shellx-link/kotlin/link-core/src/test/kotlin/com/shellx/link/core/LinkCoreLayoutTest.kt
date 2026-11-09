package com.shellx.link.core

import java.io.File
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

class LinkCoreLayoutTest {
    @Test
    fun sharedVectorsAreReachableFromTheModuleDirectory() {
        assertTrue(File("../../vectors/noise_xx.json").isFile)
        assertTrue(File("../../spec/vectors/messages.json").isFile)
    }

    @Test
    fun androidIsNotOnTheClasspath() {
        assertThrows<ClassNotFoundException> { Class.forName("android.content.Context") }
    }
}
