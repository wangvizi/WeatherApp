import SwiftUI
import WidgetKit

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: WeatherEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text(rainShort).font(.caption2.bold())
                Text(tempText).font(.caption2).foregroundStyle(.secondary)
            }
            .widgetURL(URL(string: "weatherwidget://open"))
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text(rainLine).font(.caption).bold()
                Text("\(entry.snapshot?.city.name ?? "") · \(tempText) \(entry.snapshot?.current?.weatherText ?? "")")
                    .font(.caption2).foregroundStyle(.secondary)
                if let alert = entry.snapshot?.alerts.first {
                    Text(alert.title).font(.caption2).foregroundStyle(.orange).lineLimit(1)
                }
            }
            .widgetURL(URL(string: "weatherwidget://open"))
        }
    }

    private var snap: WeatherSnapshot? { entry.snapshot }

    private var tempText: String {
        guard let c = snap?.current else { return "--°" }
        return "\(c.tempC)°"
    }

    private var rainShort: String {
        guard let m = snap?.minute, m.available else { return "无短临" }
        if m.isRaining(from: entry.date) {
            if let stop = m.minutesUntilStop(from: entry.date) { return "停\(stop)m" }
            return "雨中"
        }
        if let until = m.minutesUntilRain(from: entry.date) { return "\(until)m雨" }
        return "2h无雨"
    }

    private var rainLine: String {
        guard let m = snap?.minute, m.available else { return "分钟级降水暂不可用" }
        if m.isRaining(from: entry.date) {
            if let stop = m.minutesUntilStop(from: entry.date) { return "正在下雨 · \(stop) 分钟后停" }
            return "正在下雨 · 持续中"
        }
        if let until = m.minutesUntilRain(from: entry.date) { return "\(until) 分钟后开始下" }
        return "未来 2 小时无明显降水"
    }

    private var inlineText: String {
        guard let snap else { return "天气 · 等待更新" }
        return "\(snap.city.name) \(tempText) \(rainShort)"
    }
}
