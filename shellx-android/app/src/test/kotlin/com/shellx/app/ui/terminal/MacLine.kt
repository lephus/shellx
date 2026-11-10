package com.shellx.app.ui.terminal

import com.shellx.core.text.dropLastGrapheme
import com.shellx.link.core.TerminalInputUnit
import com.shellx.link.core.TerminalKey

/**
 * What a line editor on the Mac shows after [units]: text is appended and each backspace drops the last character
 * (what zsh and bash do at a prompt). Any other unit fails the test: a Telex or VNI rewrite is only text and backspaces.
 */
fun macLine(units: List<TerminalInputUnit>): String {
    var line = ""
    for (unit in units) {
        line = when {
            unit is TerminalInputUnit.Text -> line + unit.text
            unit is TerminalInputUnit.Key && unit.key == TerminalKey.BACKSPACE && unit.mods.isEmpty() -> line.dropLastGrapheme()
            else -> throw AssertionError("not text or a backspace: $unit")
        }
    }
    return line
}
