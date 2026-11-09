package com.shellx.core.testing

import java.lang.reflect.Modifier
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * The same exception case: the same class, and when the class declares instance fields of its own (a data class
 * case), equal values. A field holding an exception is compared the same way; a byte array by content. Never
 * compares identity: under `-ea` kotlinx-coroutines may hand a caller a copy of the exception.
 */
fun assertSameCase(expected: Throwable, actual: Throwable?, message: String? = null) {
    val prefix = message?.let { "$it: " } ?: ""
    assertNotNull(actual, "${prefix}expected ${expected::class.java.name}, got nothing")
    assertEquals(expected::class.java, actual::class.java, "${prefix}another case: $actual")
    val fields = expected::class.java.declaredFields.filter { !Modifier.isStatic(it.modifiers) && !it.isSynthetic }
    for (field in fields) {
        field.isAccessible = true
        val want = field.get(expected)
        val got = field.get(actual)
        when {
            want is Throwable -> assertSameCase(want, got as? Throwable, "${prefix}field ${field.name}")
            want is ByteArray -> assertTrue(got is ByteArray && want.contentEquals(got), "${prefix}field ${field.name}")
            else -> assertEquals(want, got, "${prefix}field ${field.name} of $actual")
        }
    }
}

/** Lower-case hex. */
fun ByteArray.hex(): String = joinToString("") { "%02x".format(it.toInt() and 0xFF) }
