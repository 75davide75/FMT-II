import SwiftUI

/// Disposizione dell'interfaccia: iPhone (o iPad in finestra stretta),
/// iPad in verticale, iPad in orizzontale.
enum DeviceLayout: Equatable {
    case compact, regular, wide

    static func resolve(horizontalSizeClass: UserInterfaceSizeClass?, width: CGFloat) -> DeviceLayout {
        guard horizontalSizeClass == .regular, width >= 700 else { return .compact }
        return width >= 1000 ? .wide : .regular
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

/// Settimana su iPad: colonne dei giorni che riempiono la larghezza.
enum WeekGridMetrics {
    static func dayColumnWidth(available: CGFloat, days: Int, timeColumn: CGFloat, minimum: CGFloat) -> CGFloat {
        guard days > 0 else { return minimum }
        return max(minimum, ((available - timeColumn) / CGFloat(days)).rounded(.down))
    }
}
