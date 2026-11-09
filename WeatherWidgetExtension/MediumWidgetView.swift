import SwiftUI
import WidgetKit

extension View {
    /// iOS 17 起小组件需要 containerBackground；16.x 直接返回原视图
    @ViewBuilder
    func widgetContainerBackground<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget, content: content)
        } else {
            self
        }
    }
}

struct MediumWidgetView: View {
    let entry: WeatherEntry

    var body: some View {
        if let snap = entry.snapshot, snap.source != .none {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snap.city.name)
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(snap.current?.tempC ?? 0)°")
                        .font(.system(size: 34, weight: .light))
                    Text(snap.current?.weatherText ?? "")
                        .font(.caption)
                    if let wind = snap.current?.windDirec {
                        Text("\(wind) \(snap.current?.windPower ?? "")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 84, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    minuteLine(snap)
                    HStack(spacing: 10) {
                        ForEach(snap.days.prefix(4)) { d in
                            VStack(spacing: 2) {
                                Text(WeatherText.weekday(d.date)).font(.caption2).foregroundStyle(.secondary)
                                Text("\(d.lowC)°/\(d.highC)°").font(.caption2.monospacedDigit())
                            }
                        }
                    }
                    if let alert = snap.alerts.first {
                        Text(alert.title)
                            .font(.caption2).lineLimit(1)
                            .foregroundStyle(.orange)
                    }
                    if snap.isStale {
                        Text("数据可能已过期").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
            }
            .padding(12)
            .widgetContainerBackground { Color.clear }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "cloud.sun").font(.title2).foregroundStyle(.secondary)
                Text("等待首次更新").font(.caption.bold())
                Text("打开一次 App 即可获取数据 · 无需填写 Key")
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetContainerBackground { Color.clear }
        }
    }

    @ViewBuilder
    private func minuteLine(_ snap: WeatherSnapshot) -> some View {
        let m = snap.minute
        if m.available {
            if m.isRaining(from: entry.date) {
                if let stop = m.minutesUntilStop(from: entry.date) {
                    Text("正在下雨 · \(stop) 分钟后停").font(.subheadline.bold())
                } else {
                    Text("正在下雨 · 持续中").font(.subheadline.bold())
                }
            } else if let until = m.minutesUntilRain(from: entry.date) {
                Text("\(until) 分钟后开始下").font(.subheadline.bold())
                Text("至少还要 \(m.minutesOfNoRain(from: entry.date) ?? until) 分钟无明显降水")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("未来 2 小时无明显降水").font(.subheadline.bold())
            }
            Text("中国天气网官方 · MPF 短临 · 起报 \(m.issuedAt?.formatted(.dateTime.hour().minute()) ?? "--")")
                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        } else {
            Text("分钟级降水暂不可用").font(.subheadline)
            Text("将使用逐小时预报兜底").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
