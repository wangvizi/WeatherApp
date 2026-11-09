import SwiftUI
import WidgetKit

@main
struct WeatherWidgetBundle: WidgetBundle {
    var body: some Widget {
        WeatherMediumWidget()
        WeatherLockScreenWidget()
    }
}

// MARK: - 主屏中尺寸：当前天气、未来四天，以及多久会下雨、多久会停

struct WeatherMediumWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeatherMediumWidget", provider: WeatherProvider()) { entry in
            MediumWidgetView(entry: entry)
                .widgetURL(URL(string: "weatherwidget://open"))
        }
        .configurationDisplayName("天气 · 分钟级降水")
        .description("当前天气、未来四天，以及多久会下雨、多久会停")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - 锁屏：显示几分钟后下雨、几分钟后停

struct WeatherLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeatherLockScreenWidget", provider: WeatherProvider()) { entry in
            LockScreenWidgetView(entry: entry)
                .widgetURL(URL(string: "weatherwidget://open"))
        }
        .configurationDisplayName("天气 · 分钟级")
        .description("锁屏显示几分钟后下雨、几分钟后停")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

struct WeatherProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry {
        WeatherEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> Void) {
        completion(WidgetRepository.entries(for: WidgetRepository.loadSnapshot()).first
                   ?? WeatherEntry(date: Date(), snapshot: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> Void) {
        let snap = WidgetRepository.loadSnapshot()
        let entries = WidgetRepository.entries(for: snap)
        // 打开一次 App 即可获取数据 · 无需填写 Key；Widget 按系统预算重试
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}
