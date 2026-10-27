import CryptoKit
import Foundation
import ShellXLinkAccount
import ShellXLinkCore

/// The account commands: `login`, `pair`, `machines`, `unpair`, `logout`.
enum Account {
    static func login(_ args: Arguments) async throws {
        guard args.flag("password-stdin") else {
            throw ProbeError("login reads the password from stdin: pass --password-stdin")
        }
        let state = try ProbeState.open(args)
        let apiText = try args.required("api")
        guard let url = URL(string: apiText), url.host != nil else { throw ProbeError("--api is not a URL") }
        let api = try RelayAPI(baseURL: url, clientVersion: Probe.clientVersion)
        let email = try args.required("email")
        let password = try PasswordInput.read()
        let key = try state.loadOrCreateKey()
        let session = try await api.login(
            email: email, password: password, deviceName: args.optional("device-name") ?? Probe.deviceName,
            clientKey: key.publicKey)
        try state.saveSession(
            StoredSession(api: url.absoluteString, userID: session.userID, deviceID: session.deviceID, token: session.token))
        Log.line("logged in as a mobile device: user \(Log.shown(session.userID)) device \(Log.shown(session.deviceID))")
    }

    static func pair(_ args: Arguments) async throws {
        let state = try ProbeState.open(args)
        let uri = try OfferFile.read(try args.required("offer-file"))
        let offer = try PairingOffer(uri: uri)
        let session = try state.loadSession()
        let key = try state.loadKey()
        Log.line("pairing with \"\(Log.shown(offer.machineName))\" (machine \(Log.shown(offer.machineID)))")
        let started = ContinuousClock.now
        let machine = try await PhonePairing.pair(
            offerURI: uri, clientKey: key.publicKey, api: try session.relayAPI(), token: session.token,
            onRequested: { id in
                Log.line("pairing request \(Log.shown(id)) sent; allow it on the Mac (or shellx.link.debug_pairing_approve)")
            })
        var machines = try state.loadMachines()
        machines.removeAll { $0.machineID == machine.machineID }
        machines.append(machine)
        try state.saveMachines(machines)
        Log.line(
            "paired with \"\(Log.shown(machine.name))\" after \(Stats.format(Stats.ms(ContinuousClock.now - started))) ms:"
                + " machine \(Log.shown(machine.machineID)) slot \(Log.shown(machine.linkSlot))"
                + " host key \(fingerprint(machine.hostKey))")
    }

    /// The machines the relay lists for this phone, next to what this state directory pinned.
    static func machines(_ args: Arguments) async throws {
        let state = try ProbeState.open(args)
        let session = try state.loadSession()
        let pinned = try state.loadMachines()
        let listed = try await session.relayAPI().machines(token: session.token)
        Log.line("relay lists \(listed.count) machine(s); \(pinned.count) pinned here")
        for machine in listed {
            let local = pinned.first { $0.machineID == machine.machineID }
            let pin: String
            switch local {
            case nil: pin = "not paired here"
            case let local? where local.linkSlot != machine.linkSlot: pin = "SLOT DIFFERS from the pinned one"
            case let local?: pin = "pinned host key \(fingerprint(local.hostKey))"
            }
            print(
                "    \(Log.shown(machine.machineID)) \"\(Log.shown(machine.name))\" platform=\(Log.shown(machine.platform))"
                    + " online=\(machine.online) slot=\(Log.shown(machine.linkSlot)) \(pin)")
        }
        for machine in pinned where !listed.contains(where: { $0.machineID == machine.machineID }) {
            print("    \(Log.shown(machine.machineID)) \"\(Log.shown(machine.name))\" pinned here, but the relay has no grant (removed?)")
        }
    }

    /// Removes this phone's grant on the relay and forgets the machine here.
    static func unpair(_ args: Arguments) async throws {
        let state = try ProbeState.open(args)
        let session = try state.loadSession()
        let machineID = try args.required("machine")
        let api = try session.relayAPI()
        if let grant = try await api.machines(token: session.token).first(where: { $0.machineID == machineID }) {
            try await api.unpair(grantID: grant.grantID, token: session.token)
            Log.line("removed the relay grant for machine \(Log.shown(machineID))")
        } else {
            Log.line("the relay has no grant for that machine")
        }
        var machines = try state.loadMachines()
        let before = machines.count
        machines.removeAll { $0.machineID == machineID }
        if machines.count != before {
            try state.saveMachines(machines)
            Log.line("forgot the machine here")
        }
    }

    /// Signs out on the relay and deletes `session.json`; keeps the key and the paired machines.
    static func logout(_ args: Arguments) async throws {
        let state = try ProbeState.open(args)
        let session = try state.loadSession()
        try await session.relayAPI().logout(token: session.token)
        state.removeSession()
        Log.line("logged out; session.json removed")
    }

    /// The first 8 bytes of SHA-256 of a public key, in hex: enough to tell keys apart in a log.
    static func fingerprint(_ key: Data) -> String {
        SHA256.hash(data: key).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
