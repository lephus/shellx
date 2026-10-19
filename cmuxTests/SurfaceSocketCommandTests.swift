import CmuxCloud
import AppKit
import CmuxSurfaceCatalogModel
import Foundation
import Testing
#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The socket face of the surface catalog, driven the way the CLI drives it: JSON-RPC
/// lines into `handleSocketLine` from a socket-worker thread, against a fake cloud
/// provider registered on the shared catalog. These pin behavior — what
/// `surface.catalog` / `surface.project` / `surface.new_terminal` / `vm.workspace_*` /
/// `vm.terminal_*` answer and what they ask the provider to do — not source shape.
@MainActor
@Suite(.serialized)
struct SurfaceSocketCommandTests {
    @Test(arguments: [
        CloudEnvDelivery.DeliveryError.outdatedShim("test-machine"),
        .receiverNotReady("starting"),
        .receiverFailed("invalid-key TEST"),
    ])
    func environmentDeliveryErrorsRemainActionable(_ failure: CloudEnvDelivery.DeliveryError) async throws {
        let response = await Task.detached {
            TerminalController.shared.v2VmCall(id: "env-error", timeoutSeconds: 5) { throw failure }
        }.value
        let object = try #require(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        let error = try Self.error(object)
        #expect(error["code"] as? String == "vm_env_delivery_failed")
        #expect(error["message"] as? String == failure.localizedDescription)
    }

    @Test func emptyWorkspaceHasARetryableSocketCode() async throws {
        let response = await Task.detached {
            TerminalController.shared.v2VmCall(id: "empty-workspace", timeoutSeconds: 5) {
                throw SurfaceCatalogError.nothingToOpen("workspace ws_pending")
            }
        }.value
        let object = try #require(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        let error = try Self.error(object)
        #expect(error["code"] as? String == "not_ready")
    }

    @Test func vmFailureDoesNotExposeBackendCredentialsOrResponseBodies() async throws {
        let response = await Task.detached {
            TerminalController.shared.v2VmCall(id: "private-error", timeoutSeconds: 5) {
                throw VMClientError.httpStatus(502, "https://private.invalid?token=secret response-body-private")
            }
        }.value
        let object = try #require(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        let error = try Self.error(object)
        #expect(error["code"] as? String == "vm_error")
        #expect((error["data"] as? [String: Any])?["http_status"] as? Int == 502)
        #expect(response.contains("HTTP 502"))
        #expect(response.contains("unreadable response omitted"))
        #expect(!response.contains("secret"))
        #expect(!response.contains("private.invalid"))
        #expect(!response.contains("response-body-private"))
    }

    @Test func typedVmFailurePreservesSafeActionCopy() async throws {
        let response = await Task.detached {
            TerminalController.shared.v2VmCall(id: "typed-error", timeoutSeconds: 5) {
                throw VMClientError.notSignedIn
            }
        }.value
        let object = try #require(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        let error = try Self.error(object)
        #expect((error["message"] as? String)?.contains("cmux auth login") == true)
    }

    @Test func tuiDaemonFailureExplainsHowToRecover() async throws {
        let response = await Task.detached {
            TerminalController.shared.v2VmCall(id: "tui-daemon-error", timeoutSeconds: 5) {
                throw CloudMachineLink.LinkError.exited(status: 1, output: "daemon unavailable")
            }
        }.value
        let object = try #require(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        let error = try Self.error(object)
        #expect(error["code"] as? String == "vm_tui_daemon_unavailable")
        #expect((error["message"] as? String)?.contains("cmux-tui") == false)
        #expect(error["message"] as? String == Self.daemonUnavailableMessage)
    }

    @Test func workspaceDaemonFailureUsesWorkspaceRecoveryCopy() async throws {
        let response = await Task.detached {
            TerminalController.shared.v2VmCall(
                id: "tui-daemon-workspace",
                timeoutSeconds: 5,
                daemonUnavailableMessage: Self.workspaceDaemonUnavailableMessage
            ) {
                throw CloudMachineLink.LinkError.timedOut
            }
        }.value
        let object = try #require(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        let error = try Self.error(object)
        #expect(error["code"] as? String == "vm_tui_daemon_unavailable")
        #expect(error["message"] as? String == Self.workspaceDaemonUnavailableMessage)
        #expect((error["message"] as? String)?.contains("cmux vm workspace new") == true)
    }

    @Test func otherDaemonLinkFailuresUseTheSameStableCategory() async throws {
        let response = await Task.detached {
            TerminalController.shared.v2VmCall(id: "tui-daemon-timeout", timeoutSeconds: 5) {
                throw CloudMachineLink.LinkError.timedOut
            }
        }.value
        let object = try #require(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        let error = try Self.error(object)
        #expect(error["code"] as? String == "vm_tui_daemon_unavailable")
        #expect(error["message"] as? String == Self.daemonUnavailableMessage)
    }

    @Test func unrelatedLinkFailuresDoNotUseDaemonCategory() async throws {
        let response = await Task.detached {
            TerminalController.shared.v2VmCall(id: "tui-client-error", timeoutSeconds: 5) {
                throw CloudMachineLink.LinkError.failureMessage("The remote workspace is unavailable; refresh and retry.")
            }
        }.value
        let object = try #require(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        let error = try Self.error(object)
        #expect(error["code"] as? String == "vm_error")
        #expect(error["message"] as? String == Self.requestFailedMessage)
    }

    @Test func daemonRejectionDoesNotUseDaemonUnavailableCategory() async throws {
        let response = await Task.detached {
            TerminalController.shared.v2VmCall(
                id: "tui-daemon-rejection",
                timeoutSeconds: 5,
                daemonUnavailableMessage: Self.workspaceDaemonUnavailableMessage
            ) {
                throw CloudMachineLink.LinkError.exited(status: 1, output: #"{"code":"selector.not_found"}"#)
            }
        }.value
        let object = try #require(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        let error = try Self.error(object)
        #expect(error["code"] as? String == "vm_error")
        #expect(error["message"] as? String == Self.requestFailedMessage)
    }

    @Test func clientExitBeforeSocketDoesNotUseDaemonCategory() async throws {
        let response = await Task.detached {
            TerminalController.shared.v2VmCall(id: "tui-client-exit", timeoutSeconds: 5) {
                throw CloudMachineLink.LinkError.exitedBeforeSocket(status: 2, output: "cmux-tui: unknown flag --carrier")
            }
        }.value
        let object = try #require(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        let error = try Self.error(object)
        #expect(error["code"] as? String == "vm_error")
        #expect(error["message"] as? String == Self.requestFailedMessage)
    }

    @Test func providerErrorCopyKeepsDetailsWithoutInternalProductNames() {
        let daemonFailure = CmuxTuiSurfaceProvider.ProviderError.terminalNotCreated(
            "cmux-tui rejected the request: retry the workspace"
        )
        #expect(daemonFailure.localizedDescription.contains(String(localized: "cloud.service.name", defaultValue: "Cloud service")))
        #expect(daemonFailure.localizedDescription.contains("retry the workspace"))

        let providerFailures: [CmuxTuiSurfaceProvider.ProviderError] = [
            .noWorkspaceOnMachine("machine"),
            daemonFailure,
            .invalidSnapshot("machine"),
            .snapshotOnly("machine"),
            .hubUnavailable,
        ]
        for failure in providerFailures {
            #expect(!failure.localizedDescription.contains("cmux-tui"))
        }

        let nonDaemonFailure = CmuxTuiSurfaceProvider.ProviderError.remoteWorkspaceNotFound("workspace-id")
        #expect(nonDaemonFailure.localizedDescription == String(
            format: String(
                localized: "cloudTree.error.remoteWorkspaceNotFound",
                defaultValue: "Remote workspace %@ is no longer available. Refresh and retry."
            ),
            "workspace-id"
        ))
        #expect(!nonDaemonFailure.localizedDescription.contains("cmux-tui"))
    }

    @Test func tunnelFailureKeepsTheSafeReasonAndDiagnosticReference() async throws {
        let response = await Task.detached {
            TerminalController.shared.v2VmCall(id: "tunnel-error", timeoutSeconds: 5) {
                throw VMClientError.httpStatus(502, #"{"error":"vm_cloud_service_unavailable","ui":{"message":"Could not start the private connection. Try again shortly."},"traceId":"75b1fc0ad4068687505292b9a4a65f7d","retryable":true,"action":"Retry the machine open shortly.","details":{"private":"credential=must-not-leak","providerMessage":"must-not-leak"}}"#)
            }
        }.value
        let object = try #require(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        let error = try Self.error(object)
        let message = try #require(error["message"] as? String)
        #expect(message.contains("Could not start the private connection"))
        #expect(message.contains("vm_cloud_service_unavailable"))
        #expect(message.contains("Retry the machine open shortly."))
        #expect(message.contains("75b1fc0ad4068687505292b9a4a65f7d"))
        #expect((error["data"] as? [String: Any])?["retryable"] as? Bool == true)
        #expect(!response.contains("must-not-leak"))
    }

    /// A cloud provider whose daemon is a notebook: every verb records what it was asked.
    private final class FakeCloudProvider: SurfaceProvider {
        let machine: SurfaceMachineID
        var info: SurfaceMachineInfo
        unowned let catalog: SurfaceCatalog
        var materialized: [(resource: SurfaceResourceID, destination: SurfaceDestination, focus: Bool)] = []
        var createdTerminals: [(command: [String]?, cwd: String?, name: String?, remoteWorkspaceID: String?)] = []
        var mutations: [String] = []
        var refreshes = 0

        init(machine: SurfaceMachineID, catalog: SurfaceCatalog, workspaces: [SurfaceRemoteWorkspace]) {
            self.machine = machine
            self.catalog = catalog
            info = SurfaceMachineInfo(
                id: machine, name: machine.rawValue, status: "running", image: "cmux-devbox", hasDesktop: false,
                memoryMb: nil, diskMb: nil, linkState: .connected, linkError: nil,
                cpuPercent: nil, memoryUsedMb: nil, diskUsedMb: nil, remoteWorkspaces: workspaces
            )
        }

        func refresh() async { refreshes += 1 }

        func materialize(_ resource: SurfaceResource, at destination: SurfaceDestination, focus: Bool) async throws -> SurfaceProjection {
            materialized.append((resource.id, destination, focus))
            return SurfaceProjection(resource: resource.id, workspaceID: destination.workspaceID, panelID: UUID())
        }

        func createTerminal(command: [String]?, cwd: String?, name: String?, remoteWorkspaceID: String?) async throws -> SurfaceResource {
            createdTerminals.append((command, cwd, name, remoteWorkspaceID))
            let workspace = (info.remoteWorkspaces ?? []).first { $0.id == remoteWorkspaceID } ?? info.remoteWorkspaces?.first
            let resource = SurfaceResource(
                id: SurfaceResourceID(machine: machine, kind: .terminal, key: "term_new_\(createdTerminals.count)"),
                title: name ?? "", detail: cwd, lifecycle: .launching, agent: nil,
                remoteWorkspace: workspace, port: nil, url: nil
            )
            // Like the real provider: the terminal exists in the catalog before it is projected.
            catalog.upsert(resource)
            return resource
        }

        func projectionDidEnd(_ projection: SurfaceProjection) {}

        func closeTerminal(_ id: SurfaceResourceID) async throws {
            mutations.append("terminal close \(id.key)")
            catalog.remove(id)
        }

        func createRemoteWorkspace(name: String?) async throws -> SurfaceRemoteWorkspace {
            mutations.append("workspace create \(name ?? "-")")
            let workspace = SurfaceRemoteWorkspace(id: "ws_created", name: name ?? "main", index: info.remoteWorkspaces?.count ?? 0, focused: false)
            info.remoteWorkspaces = (info.remoteWorkspaces ?? []) + [workspace]
            catalog.updateMachine(info, from: self)
            return workspace
        }

        func closeRemoteWorkspace(id: String) async throws {
            mutations.append("workspace close \(id)")
        }

        func renameRemoteWorkspace(id: String, name: String) async throws {
            mutations.append("workspace rename \(id) \(name)")
        }

        func renameRemoteTab(id: String, name: String) async throws {
            mutations.append("tab rename \(id) \(name)")
        }

        func renameTerminal(_ id: SurfaceResourceID, name: String) async throws {
            mutations.append("terminal rename \(id.key) \(name)")
        }
    }

    /// One registered fake machine with two workspaces: `ws_a` holds `term_a1` and
    /// `term_a2` (plus a daemon browser); `ws_b` holds `term_b`; `ws_empty` holds nothing.
    private struct Fixture {
        let machineID: String
        let machine: SurfaceMachineID
        let provider: FakeCloudProvider
        let manager: TabManager
        let workspaceID: UUID
        static let wsA = SurfaceRemoteWorkspace(id: "ws_a", name: "alpha", index: 0, focused: true)
        static let wsB = SurfaceRemoteWorkspace(id: "ws_b", name: "beta", index: 1, focused: false)
        static let wsEmpty = SurfaceRemoteWorkspace(id: "ws_empty", name: "empty", index: 2, focused: false)

        var termA1: SurfaceResourceID { SurfaceResourceID(machine: machine, kind: .terminal, key: "term_a1") }
        var termA2: SurfaceResourceID { SurfaceResourceID(machine: machine, kind: .terminal, key: "term_a2") }
        var termB: SurfaceResourceID { SurfaceResourceID(machine: machine, kind: .terminal, key: "term_b") }
        var browserA: SurfaceResourceID { SurfaceResourceID(machine: machine, kind: .browser, key: "browser_1") }

        @MainActor
        init(manager: TabManager, device: Bool = false) {
            // Locals first: a nested helper must not capture `self` before every stored
            // property is initialized.
            let machineID = "sock-" + UUID().uuidString.lowercased().prefix(8)
            let machine = device ? SurfaceMachineID.device(SurfaceDeviceInstanceID(deviceID: UUID().uuidString, tag: "default")) : .cloud(machineID)
            let catalog = SurfaceCatalog.shared
            let provider = FakeCloudProvider(machine: machine, catalog: catalog, workspaces: [Self.wsA, Self.wsB, Self.wsEmpty])
            catalog.register(provider)
            let terminal: (String, SurfaceRemoteWorkspace) -> SurfaceResource = { key, workspace in
                var resource = SurfaceResource(
                    id: SurfaceResourceID(machine: machine, kind: .terminal, key: key), title: key, detail: "/root",
                    lifecycle: .running, agent: nil, remoteWorkspace: workspace, port: nil, url: nil
                )
                resource.remoteViews = [SurfaceRemoteView(tabID: "tab_\(key)", workspace: workspace)]
                return resource
            }
            var browser = SurfaceResource(
                id: SurfaceResourceID(machine: machine, kind: .browser, key: "browser_1"), title: "docs", detail: "http://localhost:3000",
                lifecycle: .running, agent: nil, remoteWorkspace: Self.wsA, port: 3000, url: "http://localhost:3000"
            )
            browser.remoteViews = [SurfaceRemoteView(tabID: "tab_browser_1", workspace: Self.wsA)]
            catalog.replaceResources(
                [terminal("term_a1", Self.wsA), terminal("term_a2", Self.wsA), terminal("term_b", Self.wsB), browser],
                on: machine,
                info: provider.info
            )
            TerminalController.shared.setActiveTabManager(manager)
            self.machineID = machine.rawValue
            self.machine = machine
            self.provider = provider
            self.manager = manager
            self.workspaceID = manager.selectedWorkspace!.id
        }

        /// The pane belongs to this windowless fixture, so requests also name
        /// its workspace instead of asking the live-window router to find it.
        @MainActor
        var livePaneID: String? {
            // Straight from the workspace: the test TabManager is the controller's active
            // manager but is not registered with the app's window list.
            guard let workspace = manager.selectedWorkspace, let panel = workspace.focusedPanelId else { return nil }
            return workspace.paneId(forPanelId: panel)?.id.uuidString
        }

        @MainActor
        func tearDown() {
            TerminalController.shared.setActiveTabManager(nil)
            SurfaceCatalog.shared.unregister(machine: machine)
            manager.tabs.forEach { $0.teardownAllPanels() }

        }
    }

    private static func withFixture(device: Bool = false, _ body: (Fixture) async throws -> Void) async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            let previousManager = TerminalController.shared.activeTabManagerForCallerNotification()
            let betaKey = RightSidebarBetaFeatureSettings.cloudMachinesEnabledKey
            let previousBeta = UserDefaults.standard.object(forKey: betaKey)
            let app = try VaultPaneAppFixture()
            // `vm.workspace_new` admits its optimistic local workspace through the
            // active main window before it asks the provider for anything; a
            // context without a window is pruned and the call is cancelled. Bind
            // a bare window the way the shortcut tests do.
            let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
            window.identifier = NSUserInterfaceItemIdentifier("cmux.main.\(app.windowID.uuidString)")
            app.appDelegate.mainWindowContexts.values.first { $0.windowId == app.windowID }?.window = window
            defer { withExtendedLifetime(window) {} }
            defer {
                app.tearDown()
                TerminalController.shared.setActiveTabManager(previousManager)
                UserDefaults.standard.set(previousBeta, forKey: betaKey)
            }
            UserDefaults.standard.set(true, forKey: betaKey)
            let fixture = Fixture(manager: app.manager, device: device)
            defer { fixture.tearDown() }
            try await body(fixture)
        }
    }

    // MARK: - transport

    /// Sends one request the way a socket client does: off the main thread (the
    /// surface/vm verbs run on the socket-worker lane and park it while the catalog
    /// works on the main actor).
    private nonisolated static func call(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        let request: [String: Any] = ["jsonrpc": "2.0", "id": UUID().uuidString, "method": method, "params": params]
        let line = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let response = TerminalController.shared.handleSocketLine(line)
                do {
                    let object = try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any]
                    continuation.resume(returning: object ?? [:])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func ok(_ response: [String: Any]) throws -> [String: Any] {
        #expect(response["ok"] as? Bool == true, "expected success, got \(response)")
        return try #require(response["result"] as? [String: Any])
    }

    private static let daemonUnavailableMessage = String(
        localized: "socket.cloudVM.daemonUnavailable",
        defaultValue: "The Cloud VM connection is unavailable. Wake the machine or retry the command."
    )

    private static let requestFailedMessage = String(
        localized: "socket.cloudVM.requestFailed",
        defaultValue: "The Cloud VM request failed. Retry, or check the machine's status with `cmux vm ls`."
    )

    private static let workspaceDaemonUnavailableMessage = String(
        localized: "socket.cloudVM.tuiDaemonUnavailable",
        defaultValue: "Could not create a workspace on this Cloud VM. Wake the machine or retry `cmux vm workspace new`."
    )

    private static func error(_ response: [String: Any]) throws -> [String: Any] {
        #expect(response["ok"] as? Bool == false, "expected an error, got \(response)")
        return try #require(response["error"] as? [String: Any])
    }

    private static func resourceIDs(_ result: [String: Any]) -> Set<String> {
        Set(((result["resources"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String })
    }

    // MARK: - surface.catalog / vm.tree

    // MARK: - surface.project

    // MARK: - surface.new_terminal / vm.terminal_new

    // MARK: - background opens

    // MARK: - vm.workspace_*

    // MARK: - vm.terminal_close

}
