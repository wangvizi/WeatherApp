import SwiftUI

struct ContentView: View {
    @EnvironmentObject var repo: WeatherRepository
    @EnvironmentObject var settings: AppSettings
    @State private var showCityPicker = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if let snap = repo.snapshot {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            headerBar(snap)
                            minuteCard(snap)
                            if let cur = snap.current { currentCard(cur) }
                            else { placeholderCard("尚未取到真实数据", "打开 App 后会自动获取一次数据") }
                            if !snap.days.isEmpty { daysCard(snap.days) }
                            if !snap.alerts.isEmpty { alertsCard(snap.alerts) }
                            sourceCard(snap)
                        }
                        .padding()
                    }
                } else {
                    placeholderCard("等待首次更新", "打开 App 后会自动获取一次数据")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("天气 · 分钟级")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showCityPicker = true } label: {
                        Label("切换城市", systemImage: "location.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                }
            }
            .refreshable { await repo.refresh() }
            .task {
                if repo.snapshot == nil || WeatherRepository.shared.needsRefresh {
                    await repo.refresh()
                }
            }
            .overlay {
                if repo.isLoading {
                    ProgressView("正在刷新数据…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .sheet(isPresented: $showCityPicker) { CityPickerView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    // MARK: 子视图

    private func headerBar(_ snap: WeatherSnapshot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(snap.city.displayName)
                    .font(.headline)
                Text("更新于 \(snap.fetchedAt.formatted(.dateTime.hour().minute()))\(snap.isStale ? " · 数据可能已过期" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let err = repo.lastError {
                Text(err).font(.caption).foregroundStyle(.orange).lineLimit(2)
            }
        }
    }

    private func minuteCard(_ snap: WeatherSnapshot) -> some View {
        let m = snap.minute
        return VStack(alignment: .leading, spacing: 8) {
            if m.available {
                if let until = m.minutesUntilRain(), m.isRaining() == false {
                    Text("\(until) 分钟后开始下").font(.title2.bold())
                    Text("可以放心出门 · 至少还要 \(m.minutesOfNoRain() ?? until) 分钟无明显降水")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if m.isRaining(), let stop = m.minutesUntilStop() {
                    Text("正在下雨 · \(stop) 分钟后雨停").font(.title2.bold())
                } else if m.isRaining() {
                    Text("正在下雨 · 未来 2 小时持续").font(.title2.bold())
                } else {
                    Text("未来 2 小时无明显降水").font(.title2.bold())
                }
                Text("中国天气网官方短临 · 起报 \(m.issuedAt?.formatted(.dateTime.hour().minute()) ?? "--")")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("分钟级降水暂不可用").font(.headline)
                Text("将使用逐小时预报兜底").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func currentCard(_ cur: CurrentWeather) -> some View {
        HStack(alignment: .top) {
            Text("\(cur.tempC)°")
                .font(.system(size: 56, weight: .thin))
            VStack(alignment: .leading, spacing: 4) {
                Text(cur.weatherText).font(.title3)
                Text("\(cur.windDirec) \(cur.windPower)")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let h = cur.humidity {
                    Text("湿度 \(h)%").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func daysCard(_ days: [DayForecast]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("未来 \(days.count) 天").font(.headline)
            ForEach(days) { d in
                HStack {
                    Text(WeatherText.weekday(d.date)).frame(width: 44, alignment: .leading)
                    Text(d.date.formatted(.dateTime.month().day())).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(WeatherText.fromCode(d.dayWeatherCode)).font(.subheadline)
                    Spacer()
                    Text("\(d.lowC)° / \(d.highC)°").monospacedDigit()
                    if let p = d.precipProb, p >= 0 {
                        Text("\(p)%").font(.caption).foregroundStyle(.blue).frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func alertsCard(_ alerts: [WeatherAlert]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(alerts.enumerated()), id: \.offset) { _, a in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.title).font(.subheadline.bold())
                        Text(a.text).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func sourceCard(_ snap: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sourceTitle(snap.source)).font(.footnote.bold())
            Text(sourceDetail(snap.source)).font(.caption).foregroundStyle(.secondary)
            Text("目标间隔 10 分钟。WidgetKit 有系统刷新预算（通常 15~60 分钟），未越狱无法保证严格 10 分钟")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sourceTitle(_ s: DataSourceKind) -> String {
        switch s {
        case .official: return "零配置 · 中国天气网官方（无需 Key）"
        case .officialQWeather: return "官方为主 + 和风增强（已填 Key）"
        case .qWeatherOnly: return "和风天气 QWeather v7"
        case .openMeteo: return "Open-Meteo（免 Key 兜底）"
        case .none: return "等待首次更新"
        }
    }

    private func sourceDetail(_ s: DataSourceKind) -> String {
        switch s {
        case .official: return "中国天气网官方 · MPF 短临"
        case .officialQWeather: return "和风 1km 雷达临近预报（可选增强）"
        case .qWeatherOnly: return "和风 1km 雷达临近预报（可选增强）"
        case .openMeteo: return "Open-Meteo CMA GRAPES 15 分钟"
        case .none: return "打开一次 App 即可获取数据（无需填写 Key）"
        }
    }

    private func placeholderCard(_ title: String, _ sub: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.headline)
            Text(sub).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

extension WeatherRepository {
    var needsRefresh: Bool {
        guard let s = snapshot else { return true }
        return Date().timeIntervalSince(s.fetchedAt) > 10 * 60
    }
}
