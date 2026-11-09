package com.shellx.core.account

import com.shellx.link.account.PairedMachine
import com.shellx.link.core.NoiseStaticKey
import java.util.Base64
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put

/**
 * The account's secrets: the session, the phone's Link key and the paired Macs.
 *
 * Every operation holds one Mutex and runs the store call in `withContext(io)`, never on the caller's dispatcher
 * (S3 §4: no Keystore work on the main thread). The stored formats use the iPhone's key names:
 * - the session is `{"userID","deviceID","token","email"}`;
 * - the Macs are `{"version":1,"owner":"<id>","machines":[{"machineID","name","linkSlot","hostKey":"<base64>"}]}`,
 *   the host key in standard padded base64;
 * - the phone key is its 32 raw private bytes.
 */
class AccountVault(private val store: SecretStore, private val io: CoroutineDispatcher) {
    private val mutex = Mutex()

    private suspend fun <T> locked(body: () -> T): T = mutex.withLock { withContext(io) { body() } }

    // Session

    /** The stored session; null when there is none, or when it cannot be parsed. */
    suspend fun session(): StoredSession? = locked { store.read(SecretItem.SESSION)?.let(::decodeSession) }

    suspend fun setSession(session: StoredSession) {
        locked { store.write(encodeSession(session), SecretItem.SESSION) }
    }

    suspend fun clearSession() {
        locked { store.delete(SecretItem.SESSION) }
    }

    // Phone key

    /** The phone's Link static key, created on the first call (NoiseStaticKey.generate()) and the same ever after. A
     *  store that cannot be read throws instead of getting a new key. */
    suspend fun phoneKey(): NoiseStaticKey = locked {
        store.read(SecretItem.PHONE_KEY)?.let(::keyOrNull) ?: NoiseStaticKey.generate().also {
            store.write(it.rawPrivate, SecretItem.PHONE_KEY)
        }
    }

    // Paired Macs

    /** The paired Macs; [] when none are stored or the record cannot be parsed. */
    suspend fun machines(): List<PairedMachine> = locked { machinesRecord()?.machines.orEmpty() }

    suspend fun machinesOwner(): String? = locked { machinesRecord()?.owner }

    suspend fun setMachines(machines: List<PairedMachine>, owner: String) {
        locked { store.write(encodeMachines(machines, owner), SecretItem.MACHINES) }
    }

    // Wipe

    /** Deletes every item. Keeps going after a failure and rethrows the first one. */
    suspend fun wipe() {
        locked {
            var first: Exception? = null
            for (item in SecretItem.entries) {
                try {
                    store.delete(item)
                } catch (e: Exception) {
                    if (first == null) first = e
                }
            }
            first?.let { throw it }
        }
    }

    private class MachinesRecord(val owner: String, val machines: List<PairedMachine>)

    private fun machinesRecord(): MachinesRecord? = store.read(SecretItem.MACHINES)?.let(::decodeMachines)

    private companion object {
        fun keyOrNull(data: ByteArray): NoiseStaticKey? = try {
            NoiseStaticKey.fromPrivate(data)
        } catch (_: IllegalArgumentException) {
            null
        }

        fun encodeSession(session: StoredSession): ByteArray = buildJsonObject {
            put("userID", session.userId)
            put("deviceID", session.deviceId)
            put("token", session.token)
            put("email", session.email)
        }.toString().encodeToByteArray()

        /** Any parsing failure means "unreadable": null. */
        fun decodeSession(data: ByteArray): StoredSession? = try {
            val json = Json.parseToJsonElement(data.decodeToString()).jsonObject
            StoredSession(json.string("userID"), json.string("deviceID"), json.string("token"), json.string("email"))
        } catch (_: IllegalArgumentException) {
            null
        }

        fun encodeMachines(machines: List<PairedMachine>, owner: String): ByteArray = buildJsonObject {
            put("version", 1)
            put("owner", owner)
            put(
                "machines",
                buildJsonArray {
                    for (machine in machines) {
                        add(
                            buildJsonObject {
                                put("machineID", machine.machineId)
                                put("name", machine.name)
                                put("linkSlot", machine.linkSlot)
                                put("hostKey", Base64.getEncoder().encodeToString(machine.hostKey))
                            },
                        )
                    }
                },
            )
        }.toString().encodeToByteArray()

        /** Any parsing failure means "unreadable": null. The version must be there, as the iPhone's decoder needs it. */
        fun decodeMachines(data: ByteArray): MachinesRecord? = try {
            val json = Json.parseToJsonElement(data.decodeToString()).jsonObject
            (json["version"] as? JsonPrimitive)?.takeIf { !it.isString }?.int ?: throw IllegalArgumentException()
            val machines = (json["machines"] as? JsonArray ?: throw IllegalArgumentException()).map {
                val machine = it.jsonObject
                PairedMachine(
                    machineId = machine.string("machineID"),
                    name = machine.string("name"),
                    linkSlot = machine.string("linkSlot"),
                    hostKey = Base64.getDecoder().decode(machine.string("hostKey")),
                )
            }
            MachinesRecord(json.string("owner"), machines)
        } catch (_: IllegalArgumentException) {
            // SerializationException (malformed JSON, or a field of the wrong type) and bad base64 are both
            // IllegalArgumentExceptions.
            null
        }

        fun JsonObject.string(key: String): String {
            val value = this[key] as? JsonPrimitive
            require(value != null && value.isString) { "missing $key" }
            return value.content
        }
    }
}
