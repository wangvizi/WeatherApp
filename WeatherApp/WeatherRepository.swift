import Foundation
import Combine

// MARK: - 设置存储

public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private let d = UserDefaults.standard
    private enum Key {
        static let city = "selectedCity"
        static let qwKey = "qweatherKey"
        static let qwHost = "qweatherHost"
        static let manualLat = "manualLat"
        static let manualLon = "manualLon"
        static let manualCityID = "manualCityID"
        static let useLocation = "useCurrentLocation"
    }

    @Published var city: City {
        didSet { if let data = try? JSONEncoder().encode(city) { d.set(data, forKey: Key.city) } }
    }
    /// 和风天气 API Key（可完全留空）
    @Published var qweatherKey: String { didSet { d.set(qweatherKey, forKey: Key.qwKey) } }
    /// 和风 API Host，如 h2a9cf3mhs.xy.qweatherapi.com（2026 年起须用控制台分配的独立 API Host）
    @Published var qweatherHost: String { didSet { d.set(qweatherHost, forKey: Key.qwHost) } }
    /// 高级 · 手动填写坐标与城市 ID（留空则用所选城市/定位）
    @Published var manualLat: String { didSet { d.set(manualLat, forKey: Key.manualLat) } }
    @Published var manualLon: String { didSet { d.set(manualLon, forKey: Key.manualLon) } }
    @Published var manualCityID: String { didSet { d.set(manualCityID, forKey: Key.manualCityID) } }
    /// 使用当前位置（自动匹配城市 ID）
    @Published var useCurrentLocation: Bool { didSet { d.set(useCurrentLocation, forKey: Key.useLocation) } }

    private init() {
        if let data = d.data(forKey: Key.city), let c = try? JSONDecoder().decode(City.self, from: data) {
            city = c
        } else {
            city = CityData.defaultCity
        }
        qweatherKey = d.string(forKey: Key.qwKey) ?? ""
        qweatherHost = d.string(forKey: Key.qwHost) ?? ""
        manualLat = d.string(forKey: Key.manualLat) ?? ""
        manualLon = d.string(forKey: Key.manualLon) ?? ""
        manualCityID = d.string(forKey: Key.manualCityID) ?? ""
        useCurrentLocation = d.bool(forKey: Key.useLocation)
    }

    /// 实际请求用的坐标与城市 ID
    public var effectiveCity: City { city }
    public var effectiveLat: Double { Double(manualLat) ?? city.lat }
    public var effectiveLon: Double { Double(manualLon) ?? city.lon }
    public var effectiveCityID: String { manualCityID.isEmpty ? city.id : manualCityID }
    public var hasQWeather: Bool { !qweatherKey.isEmpty && !qweatherHost.isEmpty }
}

// MARK: - 数据仓库

/// 零配置 · 中国天气网官方（无需 Key）；和风为可选增强；Open-Meteo 免 Key 兜底
@MainActor
final class WeatherRepository: ObservableObject {
    static let shared = WeatherRepository()

    @Published var snapshot: WeatherSnapshot?
    @Published var isLoading = false
    @Published var lastError: String?

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    private init() {
        snapshot = SharedStore.load()
    }

    // MARK: 官方接口通用请求（需带 Referer/Cookie，返回 "var xxx = {...}" 前缀）

    private func officialJSON(url: String, cityID: String) async throws -> [String: Any] {
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        var req = URLRequest(url: u)
        req.setValue("https://www.weather.com.cn/", forHTTPHeaderField: "Referer")
        req.setValue("city=\(cityID)", forHTTPHeaderField: "Cookie")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: req)
        var text = String(decoding: data, as: UTF8.self)
        // 剥离 JS 变量前缀，截取第一个 { 到最后一个 }
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            text = String(text[start...end])
        }
        guard let d = text.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return obj
    }

    // MARK: 拉取全部数据

    func refresh(for city: City? = nil) async {
        let s = AppSettings.shared
        let target = city ?? s.effectiveCity
        let lat = s.effectiveLat, lon = s.effectiveLon
        let cityID = s.effectiveCityID
        isLoading = true
        lastError = nil
        do {
            // 官方：实况 + 逐天 + 预警 + MPF 短临，并发请求
            async let sk = fetchOfficialCurrent(cityID: cityID)
            async let daily = fetchOfficialDaily(cityID: cityID)
            async let alerts = fetchOfficialAlerts(cityID: cityID)
            async let minute = fetchOfficialMinute(lat: lat, lon: lon)

            var (cur, days, als, minF) = try await (sk, daily, alerts, minute)

            // 和风增强（可选）：补 AQI/更多天数、1km 雷达临近预报
            var source: DataSourceKind = .official
            if s.hasQWeather {
                source = .officialQWeather
                if !minF.available, let qm = try? await fetchQWeatherMinutely(lat: lat, lon: lon, key: s.qweatherKey, host: s.qweatherHost) {
                    minF = qm
                    source = .qWeatherOnly
                }
                if cur == nil, let qc = try? await fetchQWeatherNow(lat: lat, lon: lon, key: s.qweatherKey, host: s.qweatherHost) {
                    cur = qc
                }
            }
            // Open-Meteo CMA GRAPES 15 分钟兜底：官方短临不可用时
            if !minF.available {
                if let om = try? await fetchOpenMeteo(lat: lat, lon: lon) {
                    minF = om.minute
                    if cur == nil { cur = om.current }
                    if days.isEmpty { days = om.days }
                    if source == .official { source = .openMeteo }
                }
            }

            let snap = WeatherSnapshot(city: target, current: cur, days: days, minute: minF,
                                       alerts: als, source: source, fetchedAt: Date())
            snapshot = snap
            SharedStore.save(snap)
            SharedStore.reloadWidgets()
        } catch {
            lastError = "获取失败，已保留上次数据；请检查网络后重试"
        }
        isLoading = false
    }

    // MARK: 官方 · 实况（d1 sk_2d）

    private func fetchOfficialCurrent(cityID: String) async throws -> CurrentWeather? {
        let obj = try await officialJSON(url: "https://d1.weather.com.cn/sk_2d/\(cityID).html?_=\(Int(Date().timeIntervalSince1970))",
                                         cityID: cityID)
        guard let tempS = obj["temp"] as? String, let temp = Int(tempS) else { return nil }
        let code = (obj["weathercode"] as? String) ?? ""
        let windDeg = Double((obj["WD"] as? String) ?? (obj["winddegrees"] as? String) ?? "0") ?? 0
        let windName = WeatherText.windName(degrees: windDeg)
        return CurrentWeather(
            tempC: temp,
            feelsC: Int(obj["main"] as? String ?? ""),
            weatherCode: code,
            weatherText: WeatherText.fromCode(code),
            humidity: Int(obj["humidity"] as? String ?? ""),
            windDirec: windName,
            windPower: (obj["WS"] as? String) ?? (obj["windsc"] as? String) ?? "",
            rainMM: Double(obj["rain"] as? String ?? ""),
            updatedAt: Date())
    }

    // MARK: 官方 · 逐天（d1 weather_index）

    private func fetchOfficialDaily(cityID: String) async throws -> [DayForecast] {
        let obj = try await officialJSON(url: "https://d1.weather.com.cn/weather_index/\(cityID).html",
                                         cityID: cityID)
        guard let data = obj["data"] as? [String: Any],
              let fc = data["fc"] as? [[String: Any]] else { return [] }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyyMMdd"
        var out: [DayForecast] = []
        for f in fc.prefix(5) {
            guard let key = f["f"] as? String, let date = fmt.date(from: key) else { continue }
            out.append(DayForecast(
                dateKey: key, date: date,
                highC: Int(f["ft"] as? String ?? "") ?? 0,
                lowC: Int(f["nf"] as? String ?? "") ?? 0,
                dayWeatherCode: (f["fa"] as? String) ?? "",
                nightWeatherCode: (f["na"] as? String) ?? "",
                windDirecCode: (f["fd"] as? String) ?? "",
                windPower: (f["fp"] as? String) ?? "",
                precipProb: Int(f["f6"] as? String ?? "")))
        }
        return out
    }

    // MARK: 官方 · 预警（dingzhi 接口生效预警）

    private func fetchOfficialAlerts(cityID: String) async throws -> [WeatherAlert] {
        let obj = try await officialJSON(url: "https://d1.weather.com.cn/dingzhi/\(cityID).html?_=\(Int(Date().timeIntervalSince1970))",
                                         cityID: cityID)
        guard let alarm = obj["alarm"] as? [[String: Any]] else { return [] }
        return alarm.compactMap { a in
            guard let title = (a["a1"] as? String) ?? (a["alertName"] as? String) else { return nil }
            return WeatherAlert(title: title, text: (a["a2"] as? String) ?? (a["alertDetail"] as? String) ?? "",
                                issuedAt: nil)
        }
    }

    // MARK: 官方 · MPF 分钟级短临（1km、逐 6 分钟、未来 2 小时）

    private func fetchOfficialMinute(lat: Double, lon: Double) async throws -> MinuteForecast {
        let url = "http://mpf.weather.com.cn/mpf_v3/webgis/minute?lat=\(String(format: "%.4f", lat))&lon=\(String(format: "%.4f", lon))"
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        var req = URLRequest(url: u)
        req.setValue("https://www.weather.com.cn/", forHTTPHeaderField: "Referer")
        let (data, _) = try await session.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        // 兼容两种返回：{"data":{"predict":[{time,pop/rain}...]}} 或直接数组
        var raw: [[String: Any]] = []
        if let d = obj["data"] as? [String: Any] {
            raw = (d["predict"] as? [[String: Any]]) ?? (d["list"] as? [[String: Any]]) ?? []
        } else if let arr = obj["predict"] as? [[String: Any]] {
            raw = arr
        }
        let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
        let cal = Calendar.current
        var points: [MinutePoint] = []
        for item in raw {
            guard let t = item["time"] as? String, let time = fmt.date(from: t) else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: Date())
            comps.hour = cal.component(.hour, from: time)
            comps.minute = cal.component(.minute, from: time)
            guard let date = cal.date(from: comps) else { continue }
            let precip = Double((item["rain"] as? String) ?? (item["pop"] as? String) ?? (item["value"] as? String) ?? "0") ?? 0
            points.append(MinutePoint(time: date, precipMM: precip))
        }
        guard !points.isEmpty else { throw URLError(.cannotParseResponse) }
        return MinuteForecast(issuedAt: Date(), points: points, available: true, source: .official)
    }

    // MARK: 和风 v7 · 分钟级雷达（可选增强）

    private func fetchQWeatherMinutely(lat: Double, lon: Double, key: String, host: String) async throws -> MinuteForecast {
        let url = "https://\(host)/v7/minutely/5m?location=\(String(format: "%.2f,%.2f", lon, lat))&key=\(key)"
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: u)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["minutely"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        let iso = ISO8601DateFormatter()
        var points: [MinutePoint] = []
        for item in list {
            guard let ts = item["fxTime"] as? String, let date = iso.date(from: ts) else { continue }
            let precip = Double((item["precip"] as? String) ?? "0") ?? 0
            points.append(MinutePoint(time: date, precipMM: precip))
        }
        guard !points.isEmpty else { throw URLError(.cannotParseResponse) }
        return MinuteForecast(issuedAt: Date(), points: points, available: true, source: .qWeatherOnly)
    }

    private func fetchQWeatherNow(lat: Double, lon: Double, key: String, host: String) async throws -> CurrentWeather? {
        let url = "https://\(host)/v7/weather/now?location=\(String(format: "%.2f,%.2f", lon, lat))&key=\(key)"
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: u)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let now = obj["now"] as? [String: Any],
              let temp = Int(now["temp"] as? String ?? "") else { return nil }
        return CurrentWeather(tempC: temp, feelsC: Int(now["feelsLike"] as? String ?? ""),
                              weatherCode: (now["icon"] as? String) ?? "",
                              weatherText: (now["text"] as? String) ?? "",
                              humidity: Int(now["humidity"] as? String ?? ""),
                              windDirec: (now["windDir"] as? String) ?? "",
                              windPower: (now["windSpeed"] as? String) ?? "",
                              rainMM: Double(now["precip"] as? String ?? ""),
                              updatedAt: Date())
    }

    // MARK: Open-Meteo · CMA GRAPES 15 分钟（免 Key 兜底）

    private struct OpenMeteoResult {
        var current: CurrentWeather?
        var minute: MinuteForecast
        var days: [DayForecast]
    }

    private func fetchOpenMeteo(lat: Double, lon: Double) async throws -> OpenMeteoResult {
        let url = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=\(String(format: "%.4f", lat))&longitude=\(String(format: "%.4f", lon))"
            + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m"
            + "&minutely_15=precipitation,precipitation_probability"
            + "&daily=temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max,wind_direction_10m_dominant"
            + "&forecast_minutely_15=true&timezone=Asia%2FShanghai&forecast_days=5"
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: u)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        let iso = ISO8601DateFormatter()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]

        // current
        var current: CurrentWeather?
        if let c = obj["current"] as? [String: Any] {
            let deg = (c["wind_direction_10m"] as? Double) ?? 0
            current = CurrentWeather(
                tempC: Int((c["temperature_2m"] as? Double) ?? 0),
                feelsC: Int((c["apparent_temperature"] as? Double) ?? 0),
                weatherCode: String(Int((c["weather_code"] as? Double) ?? -1)),
                weatherText: Self.openMeteoCodeText(Int((c["weather_code"] as? Double) ?? -1)),
                humidity: Int((c["relative_humidity_2m"] as? Double) ?? 0),
                windDirec: WeatherText.windName(degrees: deg),
                windPower: String(format: "%.0f", (c["wind_speed_10m"] as? Double) ?? 0),
                rainMM: nil, updatedAt: Date())
        }

        // minutely_15
        var points: [MinutePoint] = []
        if let m = obj["minutely_15"] as? [String: Any],
           let times = m["time"] as? [String],
           let precip = m["precipitation"] as? [Double] {
            for (i, t) in times.enumerated() where i < precip.count {
                if let date = iso.date(from: t) {
                    points.append(MinutePoint(time: date, precipMM: precip[i]))
                }
            }
        }
        let minute = MinuteForecast(issuedAt: Date(), points: points,
                                   available: !points.isEmpty, source: .openMeteo)

        // daily
        var days: [DayForecast] = []
        if let d = obj["daily"] as? [String: Any],
           let times = d["time"] as? [String],
           let highs = d["temperature_2m_max"] as? [Double],
           let lows = d["temperature_2m_min"] as? [Double],
           let codes = d["weather_code"] as? [Double] {
            for i in 0..<min(times.count, 5) {
                guard let date = fmt.date(from: times[i]) else { continue }
                let key = times[i].replacingOccurrences(of: "-", with: "")
                days.append(DayForecast(
                    dateKey: key, date: date,
                    highC: Int(highs[i].rounded()), lowC: Int(lows[i].rounded()),
                    dayWeatherCode: String(Int(codes[i])),
                    nightWeatherCode: String(Int(codes[i])),
                    windDirecCode: String(Int((d["wind_direction_10m_dominant"] as? [Double])?[i] ?? 0)),
                    windPower: "",
                    precipProb: Int(((d["precipitation_probability_max"] as? [Double])?[i]) ?? -1)))
            }
        }
        return OpenMeteoResult(current: current, minute: minute, days: days)
    }

    static func openMeteoCodeText(_ code: Int) -> String {
        switch code {
        case 0: return "晴"
        case 1, 2: return "多云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51...57: return "毛毛雨"
        case 61...63: return code == 63 ? "大雨" : "雨"
        case 65...67: return "暴雨"
        case 71...77: return "雪"
        case 80...82: return "阵雨"
        case 95...99: return "雷阵雨"
        default: return ""
        }
    }

    // MARK: 城市搜索（中国天气网官方 toy1）

    struct SearchCity: Identifiable, Hashable {
        var id: String { cityID }
        let cityID: String
        let name: String
        let city: String
        let province: String
    }

    func searchCities(keyword: String) async throws -> [SearchCity] {
        let kw = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let url = "https://toy1.weather.com.cn/search?cityname=\(kw)&type=1&_=\(Int(Date().timeIntervalSince1970))"
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        var req = URLRequest(url: u)
        req.setValue("https://www.weather.com.cn/", forHTTPHeaderField: "Referer")
        let (data, _) = try await session.data(for: req)
        var text = String(decoding: data, as: UTF8.self)
        if let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]") {
            text = String(text[start...end])
        }
        guard let d = text.data(using: .utf8),
              let arr = try JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return [] }
        return arr.compactMap { item in
            guard let cityID = item["cityid"] as? String, !cityID.isEmpty else { return nil }
            return SearchCity(cityID: cityID,
                              name: (item["key"] as? String) ?? (item["city"] as? String) ?? "",
                              city: (item["city"] as? String) ?? "",
                              province: (item["up"] as? String) ?? "")
        }
    }
}
