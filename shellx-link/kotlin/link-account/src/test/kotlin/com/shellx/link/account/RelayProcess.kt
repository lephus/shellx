package com.shellx.link.account

import java.io.IOException
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.ServerSocket
import java.net.URI
import java.util.concurrent.TimeUnit
import kotlin.test.fail

/** A `cmux-relay serve` child process bound to a free loopback port (`RelayIntegrationTests.swift`). */
class RelayProcess private constructor(
    /** `ws://127.0.0.1:<port>/v1/relay`. */
    val url: URI,
    private val process: Process,
) {
    /** Stops and reaps the relay, forcibly after 5 s. */
    fun stop() {
        process.destroy()
        if (!process.waitFor(5, TimeUnit.SECONDS)) {
            process.destroyForcibly()
            process.waitFor(5, TimeUnit.SECONDS)
        }
    }

    companion object {
        /**
         * Starts `<binary> serve` with only `CMUX_RELAY_HMAC_SECRET`, `CMUX_RELAY_ISSUER` and `CMUX_RELAY_BIND` in its
         * environment, output discarded. Healthy when `GET /healthz` answers 200 within 10 s; otherwise it is stopped
         * and the test fails.
         */
        fun start(binary: String, secret: String): RelayProcess {
            val port = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1")).use { it.localPort }
            val builder = ProcessBuilder(binary, "serve")
                .redirectOutput(ProcessBuilder.Redirect.DISCARD)
                .redirectError(ProcessBuilder.Redirect.DISCARD)
            builder.environment().apply {
                clear()
                put("CMUX_RELAY_HMAC_SECRET", secret)
                put("CMUX_RELAY_ISSUER", TestTicketMinter.ISSUER)
                put("CMUX_RELAY_BIND", "127.0.0.1:$port")
            }
            val relay = RelayProcess(URI("ws://127.0.0.1:$port/v1/relay"), builder.start())
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
            while (true) {
                if (!relay.process.isAlive) fail("cmux-relay exited before it was healthy")
                if (isHealthy(port)) return relay
                if (System.nanoTime() > deadline) {
                    relay.stop()
                    fail("cmux-relay did not become healthy")
                }
                Thread.sleep(50)
            }
        }

        private fun isHealthy(port: Int): Boolean {
            val connection = URI("http://127.0.0.1:$port/healthz").toURL().openConnection() as HttpURLConnection
            return try {
                connection.connectTimeout = 500
                connection.readTimeout = 500
                connection.responseCode == 200
            } catch (_: IOException) {
                false
            } finally {
                connection.disconnect()
            }
        }
    }
}
