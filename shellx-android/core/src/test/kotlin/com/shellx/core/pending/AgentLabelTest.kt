package com.shellx.core.pending

import kotlin.test.Test
import kotlin.test.assertEquals

class AgentLabelTest {
    @Test fun knownAgentsNamed() {
        assertEquals("Claude Code", AgentLabel.of("claude").text)
        assertEquals("Codex", AgentLabel.of("codex").text)
    }

    @Test fun unknownAgentKeptAsIs() {
        assertEquals("gemini", AgentLabel.of("gemini").text)
        assertEquals("Claude", AgentLabel.of("Claude").text, "wire names are exact")
        assertEquals("", AgentLabel.of("").text)
    }
}
