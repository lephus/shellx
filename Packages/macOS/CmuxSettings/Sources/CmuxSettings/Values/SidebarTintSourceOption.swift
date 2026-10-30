import ShellXBrand

/// Where the left sidebar's color comes from: the terminal theme or the
/// user's own tint. Persisted under `sidebarTintSource`.
public typealias SidebarTintSourceOption = ShellXSidebarTintSource

extension ShellXSidebarTintSource: SettingCodable {}
