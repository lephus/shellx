// ShellX Notifier: posts one automation banner, or opens the link of a clicked one.
//
// Post:  ShellX Notifier --title T --body B --url U --group G
//        Asks for permission on first use, adds one notification request
//        (thread id G, userInfo["url"] = U) and quits when the add completes.
// Click: macOS relaunches the helper without arguments and delivers the
//        response to the delegate, which opens U and quits.
// Both paths are bounded by a watchdog, so a stuck prompt never leaves the
// helper running.

import AppKit
import UserNotifications

struct NotifierRequest: Sendable {
    let title: String
    let body: String
    let url: String
    let group: String

    /// The request in `arguments`, or `nil` when `--title` is absent (a click launch).
    init?(arguments: [String]) {
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            if ["--title", "--body", "--url", "--group"].contains(arg), index + 1 < arguments.count {
                values[arg] = arguments[index + 1]
                index += 2
            } else {
                index += 1
            }
        }
        guard let title = values["--title"] else { return nil }
        self.title = title
        body = values["--body"] ?? ""
        url = values["--url"] ?? ""
        group = values["--group"] ?? ""
    }
}

@MainActor
final class NotifierDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private static let postTimeout: Duration = .seconds(120)
    private static let clickTimeout: Duration = .seconds(15)

    private let request: NotifierRequest?

    init(request: NotifierRequest?) {
        self.request = request
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Set before launch completes so a click that launched the helper is delivered.
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let request {
            startWatchdog(Self.postTimeout, message: "timed out waiting for notification permission")
            Task { await Self.post(request) }
        } else {
            startWatchdog(Self.clickTimeout, message: nil)
        }
    }

    private func startWatchdog(_ timeout: Duration, message: String?) {
        Task {
            try? await Task.sleep(for: timeout)
            if let message { Self.fail(message) }
            exit(0)
        }
    }

    private static func post(_ request: NotifierRequest) async {
        let center = UNUserNotificationCenter.current()
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                fail("notifications are turned off for ShellX Notifier in System Settings")
            }
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.threadIdentifier = request.group
            content.userInfo = ["url": request.url]
            content.sound = .default
            let identifier = "\(request.group)-\(UUID().uuidString)"
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            exit(0)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("ShellX Notifier: \(message)\n".utf8))
        exit(1)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let link = response.notification.request.content.userInfo["url"] as? String
        await MainActor.run {
            // Only ShellX's own links: the helper never becomes a general URL opener.
            if let link, let url = URL(string: link), url.scheme == "shellx" {
                NSWorkspace.shared.open(url)
            }
            if self.request == nil { exit(0) }
        }
    }
}

let app = NSApplication.shared
let delegate = NotifierDelegate(request: NotifierRequest(arguments: Array(CommandLine.arguments.dropFirst())))
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
