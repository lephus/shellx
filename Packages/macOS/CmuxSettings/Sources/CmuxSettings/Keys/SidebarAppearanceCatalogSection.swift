import Foundation
import ShellXBrand

/// Settings under the dotted-id prefix `sidebarAppearance.*`.
public struct SidebarAppearanceCatalogSection: SettingCatalogSection {
    /// ShellX: off by default, so the sidebar draws the opaque `panel` token
    /// (spec §7.4) instead of the terminal background. A stored choice wins.
    public let matchTerminalBackground = DefaultsKey<Bool>(
        id: "sidebarAppearance.matchTerminalBackground",
        defaultValue: false,
        userDefaultsKey: "sidebarMatchTerminalBackground"
    )

    /// ShellX: the opaque `panel` token (#100b1d), mirroring
    /// `WindowChromeSidebarTintDefaults`.
    public let tintColorHex = DefaultsKey<String>(
        id: "sidebarAppearance.tintColor",
        defaultValue: ShellXPalette.panel.hexString.uppercased(),
        userDefaultsKey: "sidebarTintHex"
    )

    public let lightModeTintColorHex = DefaultsKey<String>(
        id: "sidebarAppearance.lightModeTintColor",
        defaultValue: "",
        userDefaultsKey: "sidebarTintHexLight"
    )

    public let darkModeTintColorHex = DefaultsKey<String>(
        id: "sidebarAppearance.darkModeTintColor",
        defaultValue: "",
        userDefaultsKey: "sidebarTintHexDark"
    )

    public let tintOpacity = DefaultsKey<Double>(
        id: "sidebarAppearance.tintOpacity",
        defaultValue: 1.0,
        userDefaultsKey: "sidebarTintOpacity"
    )

    public let blurOpacity = DefaultsKey<Double>(
        id: "sidebarAppearance.blurOpacity",
        defaultValue: 1.0,
        userDefaultsKey: "sidebarBlurOpacity"
    )

    public let cornerRadius = DefaultsKey<Double>(
        id: "sidebarAppearance.cornerRadius",
        defaultValue: 0.0,
        userDefaultsKey: "sidebarCornerRadius"
    )

    public let preset = DefaultsKey<SidebarPresetOption>(
        id: "sidebarAppearance.preset",
        defaultValue: .nativeSidebar,
        userDefaultsKey: "sidebarPreset"
    )

    public let material = DefaultsKey<SidebarMaterialOption>(
        id: "sidebarAppearance.material",
        defaultValue: .sidebar,
        userDefaultsKey: "sidebarMaterial"
    )

    public let blendMode = DefaultsKey<SidebarBlendModeOption>(
        id: "sidebarAppearance.blendMode",
        defaultValue: .withinWindow,
        userDefaultsKey: "sidebarBlendMode"
    )

    public let state = DefaultsKey<SidebarStateOption>(
        id: "sidebarAppearance.state",
        defaultValue: .followWindow,
        userDefaultsKey: "sidebarState"
    )

    public init() {}
}
