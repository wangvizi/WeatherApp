import Foundation
import UIKit

/// 后台刷新：BGTaskScheduler（标识 cn.weatherwidget.refresh）
/// 目标间隔 10 分钟。WidgetKit 有系统刷新预算（通常 15~60 分钟），未越狱无法保证严格 10 分钟
enum BackgroundRefresh {
    static let taskIdentifier = "cn.weatherwidget.refresh"

    static func register() {
        BGTaskSchedulerCompat.register(taskIdentifier: taskIdentifier) { task in
            let app = UIApplication.shared
            let bg = app.beginBackgroundTask(withName: "cn.weatherwidget.refresh")
            Task {
                await WeatherRepository.shared.refresh()
                await MainActor.run {
                    task.setTaskCompleted(success: true)
                    app.endBackgroundTask(bg)
                    schedule()
                }
            }
        }
        schedule()
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 10 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

// BGTaskScheduler 在 iOS 15+ 可用；做一层薄封装便于编译期检查
#if canImport(BackgroundTasks)
import BackgroundTasks
enum BGTaskSchedulerCompat {
    static func register(taskIdentifier: String, handler: @escaping (BGAppRefreshTask) -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            handler(task as! BGAppRefreshTask)
        }
    }
}
#else
enum BGTaskSchedulerCompat {
    static func register(taskIdentifier: String, handler: @escaping (Any) -> Void) {}
}
#endif
