import Foundation

extension Array where Element == CuratedSettingEntry {
    /// Search entries of the Settings › Mobile rows that a host pairing phones through ShellX Link hides
    /// (``SettingsHostActions/pairsPhonesThroughShellXLink``): the iOS pairing host and its port, display
    /// name, folder access and browser tunnel, and phone push.
    static let shellXLinkHiddenMobileEntryIDs: Set<String> = [
        "iOSPairingHost",
        "iOSPairingPort",
        "iOSPairingDisplayName",
        "artifactFolderAccess",
        "browserTunnelAllowOtherHosts",
        "phone-push-forwarding",
        "phone-push-mode",
        "phone-push-hide-content",
    ]

    /// These entries as a host's Settings › Mobile shows them. Unchanged unless the host pairs phones through
    /// ShellX Link: then Mobile has only its "Pair iPhone" row, so the hidden rows leave search and the
    /// pairing entry takes that row's text.
    ///
    /// - Parameter throughShellXLink: The host's ``SettingsHostActions/pairsPhonesThroughShellXLink``.
    public func forMobilePairing(throughShellXLink: Bool) -> [CuratedSettingEntry] {
        guard throughShellXLink else { return self }
        return compactMap { entry -> CuratedSettingEntry? in
            guard entry.section == .mobile else { return entry }
            if Self.shellXLinkHiddenMobileEntryIDs.contains(entry.id) { return nil }
            return entry.id == MobileSection.pairDeviceEntryID ? .shellXLinkPairing : entry
        }
    }
}

extension CuratedSettingEntry {
    /// Settings › Mobile › Pair iPhone for a host pairing phones through ShellX Link.
    static var shellXLinkPairing: CuratedSettingEntry {
        CuratedSettingEntry(
            section: .mobile,
            id: MobileSection.pairDeviceEntryID,
            title: MobileSection.shellXLinkPairingTitle,
            detailText: MobileSection.shellXLinkPairingSubtitle,
            synonyms: """
            Pair iPhone pair pairing add device phone qr qr code scan camera iphone ipad ios mobile shellx link \
            allow paired phones remove
            """
        )
    }
}
