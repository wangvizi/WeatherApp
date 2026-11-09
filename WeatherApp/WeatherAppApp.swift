import SwiftUI
import UIKit

@main
struct WeatherAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var repo = WeatherRepository.shared
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(repo)
                .environmentObject(settings)
                .onOpenURL { url in
                    // weatherwidget://open —— 小组件点击跳回 App
                    if url.scheme == "weatherwidget" {
                        Task { await repo.refresh() }
                    }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundRefresh.register()
        return true
    }
}
