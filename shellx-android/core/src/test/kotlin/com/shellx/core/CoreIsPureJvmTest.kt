package com.shellx.core

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

class CoreIsPureJvmTest {
    @Test
    fun androidIsNotOnTheClasspath() {
        assertThrows<ClassNotFoundException> { Class.forName("android.content.Context") }
    }
}
