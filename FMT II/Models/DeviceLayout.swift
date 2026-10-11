import SwiftUI

/// Disposizione dell'interfaccia: iPhone (o iPad in finestra stretta),
/// iPad in verticale, iPad in orizzontale.
enum DeviceLayout: Equatable {
    case compact, regular, wide

    /// iPad = entrambe le size class regolari (un iPhone grande in orizzontale
    /// ha quella verticale compatta e resta col layout iPhone).
    static func resolve(horizontalSizeClass: UserInterfaceSizeClass?, verticalSizeClass: UserInterfaceSizeClass?,
                        width: CGFloat) -> DeviceLayout {
        guard horizontalSizeClass == .regular, verticalSizeClass == .regular, width >= 700 else { return .compact }
        // 1100: ogni iPad in orizzontale è ≥ 1133 pt, in verticale ≤ 1032 pt.
        return width >= 1100 ? .wide : .regular
    }

    var isIPadLayout: Bool { self != .compact }
}

private struct DeviceLayoutKey: EnvironmentKey {
    static let defaultValue: DeviceLayout = .compact
}

extension EnvironmentValues {
    var deviceLayout: DeviceLayout {
        get { self[DeviceLayoutKey.self] }
        set { self[DeviceLayoutKey.self] = newValue }
    }
}
