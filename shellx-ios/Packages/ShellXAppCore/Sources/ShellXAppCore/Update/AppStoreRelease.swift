import Foundation

/// The app as the App Store lists it now: its version and its store page.
public struct AppStoreRelease: Equatable, Sendable {
    public var version: String
    public var storeURL: URL

    public init(version: String, storeURL: URL) {
        self.version = version
        self.storeURL = storeURL
    }

    /// The iTunes lookup for `bundleID` in the store of `country` (two letters, lowercase); without a
    /// country the lookup reads the US store.
    public static func lookupURL(bundleID: String, country: String?) -> URL {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [URLQueryItem(name: "bundleId", value: bundleID)]
            + (country.map { [URLQueryItem(name: "country", value: $0)] } ?? [])
        return components.url!
    }

    /// The release in a lookup's answer; nil when the app is not on that store, or when the answer
    /// is not one this app can read.
    public static func parse(_ data: Data) -> AppStoreRelease? {
        struct Answer: Decodable {
            struct Result: Decodable {
                var version: String?
                var trackViewUrl: String?
            }
            var results: [Result]
        }
        guard let result = (try? JSONDecoder().decode(Answer.self, from: data))?.results.first,
              let version = result.version, let page = result.trackViewUrl, let storeURL = URL(string: page)
        else { return nil }
        return AppStoreRelease(version: version, storeURL: storeURL)
    }
}

/// Compares `major.minor.patch` versions as the App Store and `CFBundleShortVersionString` give them.
public enum AppVersion {
    /// True when `candidate` is above `installed`, part by part, a missing part counting as 0. False
    /// when either is not dot-separated numbers: nothing is offered on a version this app cannot read.
    public static func isNewer(_ candidate: String, than installed: String) -> Bool {
        guard let new = parts(candidate), let old = parts(installed) else { return false }
        for index in 0..<max(new.count, old.count) {
            let (a, b) = (index < new.count ? new[index] : 0, index < old.count ? old[index] : 0)
            if a != b { return a > b }
        }
        return false
    }

    private static func parts(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }
    }
}
