//
//  FMT_IIApp.swift
//  FMT II
//
//  Created by Davide Sogos on 28/06/26.
//

import SwiftUI
import UserNotifications

/// Handles notification presentation (so reminders also show while the app is open).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Ask early so permission is already granted by the time a reminder is
        // scheduled (otherwise the first scheduled notification is silently dropped).
        #if DEBUG
        // Durante il seed per gli screenshot non chiedere il permesso notifiche,
        // così il dialog di sistema non compare nelle catture.
        let seedingForScreenshots = ProcessInfo.processInfo.arguments.contains("-FMTSeedDemo")
            || ProcessInfo.processInfo.environment["FMT_SEED_DEMO"] == "1"
        #else
        let seedingForScreenshots = false
        #endif
        if !seedingForScreenshots {
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

@main
struct FMT_IIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("dynamicTypeLevel") private var dynamicTypeLevel = 0

    /// App-wide text-size override (nil = follow the system). Capped at "Enorme".
    private var overrideTypeSize: DynamicTypeSize? {
        switch dynamicTypeLevel {
        case 1: return .xLarge
        case 2: return .xxLarge
        case 3: return .xxxLarge
        default: return nil
        }
    }

    init() {
        // Segmented control nello stile Aurora: pill selezionata tinta di blu.
        let seg = UISegmentedControl.appearance()
        seg.selectedSegmentTintColor = UIColor(red: 0.306, green: 0.486, blue: 0.965, alpha: 1)
        seg.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modifier(FixedTypeSize(size: overrideTypeSize))
                // Force Italian date/number formatting (weekdays, months, pickers)
                // regardless of the device language.
                .environment(\.locale, Locale(identifier: "it_IT"))
        }
    }
}
