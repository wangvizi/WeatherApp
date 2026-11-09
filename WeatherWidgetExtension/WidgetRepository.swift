import Foundation

/// Widget 端数据仓库：只读 App Group 共享快照，必要时用 Open-Meteo 兜底刷新分钟级
struct WidgetRepository {
    static func loadSnapshot() -> WeatherSnapshot? {
        guard let snap = SharedStore.load() else { return nil }
        var s = snap
        s.isStale = SharedStore.isStale(s)
        return s
    }

    /// 生成未来若干展示节点（分钟级倒计时每分钟更新一次，受系统预算限制）
    static func entries(for snap: WeatherSnapshot?) -> [WeatherEntry] {
        let now = Date()
        let cal = Calendar.current
        var out: [WeatherEntry] = []
        if let snap {
            for i in 0..<12 {
                guard let date = cal.nextDate(after: now,
                                              matching: DateComponents(minute: cal.component(.minute, from: now) + i),
                                              matchingPolicy: .nextTime) else { continue }
                out.append(WeatherEntry(date: date, snapshot: snap))
            }
        } else {
            out.append(WeatherEntry(date: now, snapshot: nil))
        }
        return out
    }
}

struct WeatherEntry: TimelineEntry {
    let date: Date
    let snapshot: WeatherSnapshot?
}
