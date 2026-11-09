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

    // MARK: 官方接口：拉取文本并解析多个 "var NAME = {...};" 片段

    private func officialText(url: String, cityID: String) async throws -> String {
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        var req = URLRequest(url: u)
        req.setValue("https://www.weather.com.cn/", forHTTPHeaderField: "Referer")
        req.setValue("city=\(cityID)", forHTTPHeaderField: "Cookie")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: req)
        return String(decoding: data, as: UTF8.self)
    }

    /// 解析 JS 文本中所有顶层 `var name = {…}/[…]` 对象
    private func parseJSVars(_ text: String) -> [String: Any] {
        let chars = Array(text)
        var out: [String: Any] = [:]
        var i = 0
        while i + 3 < chars.count {
            if chars[i] == "v", chars[i+1] == "a", chars[i+2] == "r", chars[i+3] == " " {
                var j = i + 4
                var name = ""
                while j < chars.count, chars[j] != "=" { name.append(chars[j]); j += 1 }
                name = name.trimmingCharacters(in: .whitespaces)
                j += 1
                while j < chars.count, chars[j] == " " { j += 1 }
                guard j < chars.count, chars[j] == "{" || chars[j] == "[" else { i += 1; continue }
                let open = chars[j]
                let close: Character = open == "{" ? "}" : "]"
                var depth = 0, k = j, inStr = false, esc = false
                while k < chars.count {
                    let c = chars[k]
                    if inStr {
                        if esc { esc = false }
                        else if c == "\\" { esc = true }
                        else if c == "\"" { inStr = false }
                    } else {
                        if c == "\"" { inStr = true }
                        else if c == open { depth += 1 }
                        else if c == close { depth -= 1; if depth == 0 { break } }
                    }
                    k += 1
                }
                if k < chars.count, depth == 0 {
                    let jsonStr = String(chars[j...k])
                    if let dd = jsonStr.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: dd) {
                        out[name] = obj
                    }
                }
                i = k + 1
            } else { i += 1 }
        }
        return out
    }

    /// dingzhi/alarm 变量名带城市 ID 后缀（如 cityDZ101260307），按前缀查找
    private func findVar(_ vars: [String: Any], prefix: String) -> Any? {
        if let v = vars[prefix] { return v }
        if let key = vars.keys.first(where: { $0.hasPrefix(prefix) }) { return vars[key] }
        return nil
    }

    // MARK: 拉取全部数据（单项失败不阻断，官方全挂时 Open-Meteo 兜底）

    func refresh(for city: City? = nil) async {
        let s = AppSettings.shared
        let target = city ?? s.city
        let lat = s.effectiveLat, lon = s.effectiveLon
        let cityID = s.effectiveCityID
        isLoading = true
        lastError = nil
        do {
            async let sk = fetchOfficialCurrent(cityID: cityID)
            async let wi = fetchOfficialWeatherIndex(cityID: cityID)
            async let mpf = fetchOfficialMinute(lat: lat, lon: lon)

            let cur = try? await sk
            let (days, als) = (try? await wi) ?? ([], [])
            let minF = (try? await mpf) ?? MinuteForecast()
            var source: DataSourceKind = .official

            var finalCur = cur
            var finalDays = days
            var finalMin = minF

            // 和风增强（可选）：补分钟级/实况
            if s.hasQWeather {
                if !finalMin.available, let qm = try? await fetchQWeatherMinutely(lat: lat, lon: lon, key: s.qweatherKey, host: s.qweatherHost) {
                    finalMin = qm
                    source = .officialQWeather
                }
                if finalCur == nil, let qc = try? await fetchQWeatherNow(lat: lat, lon: lon, key: s.qweatherKey, host: s.qweatherHost) {
                    finalCur = qc
                    source = .officialQWeather
                }
            }
            // Open-Meteo CMA GRAPES 15 分钟兜底：官方全部不可用时
            if finalCur == nil && finalDays.isEmpty && !finalMin.available {
                if let om = try? await fetchOpenMeteo(lat: lat, lon: lon) {
                    finalCur = om.current
                    finalDays = om.days
                    finalMin = om.minute
                    source = .openMeteo
                }
            }
            guard finalCur != nil || !finalDays.isEmpty || finalMin.available else {
                throw URLError(.cannotParseResponse)
            }

            let snap = WeatherSnapshot(city: target, current: finalCur, days: finalDays, minute: finalMin,
                                       alerts: als, source: source, fetchedAt: Date())
            snapshot = snap
            SharedStore.save(snap)
            SharedStore.reloadWidgets()
        } catch {
            lastError = "获取失败，已保留上次数据；请检查网络后重试"
        }
        isLoading = false
    }

    // MARK: 官方 · 实况（d1 sk_2d → var dataSK）

    private func fetchOfficialCurrent(cityID: String) async throws -> CurrentWeather? {
        let text = try await officialText(url: "https://d1.weather.com.cn/sk_2d/\(cityID).html?_=\(Int(Date().timeIntervalSince1970))",
                                         cityID: cityID)
        guard let sk = parseJSVars(text)["dataSK"] as? [String: Any],
              let temp = Double(sk["temp"] as? String ?? "") else { return nil }
        let code = Self.stripCode(sk["weathercode"] as? String ?? "")
        return CurrentWeather(
            tempC: Int(temp.rounded()),
            weatherCode: code,
            weatherText: (sk["weather"] as? String) ?? WeatherText.fromCode(code),
            humidity: Int((sk["SD"] as? String ?? "").replacingOccurrences(of: "%", with: "")),
            windDirec: (sk["WD"] as? String) ?? "",
            windPower: (sk["WS"] as? String) ?? "",
            rainMM: Double(sk["rain"] as? String ?? ""),
            updatedAt: Date())
    }

    // MARK: 官方 · 逐天 + 预警（d1 weather_index → var fc / alarmDZ）

    private func fetchOfficialWeatherIndex(cityID: String) async throws -> ([DayForecast], [WeatherAlert]) {
        let text = try await officialText(url: "https://d1.weather.com.cn/weather_index/\(cityID).html",
                                          cityID: cityID)
        let vars = parseJSVars(text)
        let days = Self.parseDaily(vars["fc"] as? [String: Any])
        let alerts = Self.parseAlerts(findVar(vars, prefix: "alarmDZ") as? [String: Any])
        return (days, alerts)
    }

    static func parseDaily(_ fc: [String: Any]?) -> [DayForecast] {
        guard let arr = fc?["f"] as? [[String: Any]] else { return [] }
        let fmt = DateFormatter()
        fmt.dateFormat = "MM/d"
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let thisYear = cal.component(.year, from: now)
        var out: [DayForecast] = []
        for f in arr.prefix(5) {
            guard let fi = f["fi"] as? String, let parsed = fmt.date(from: fi) else { continue }
            let p = cal.dateComponents([.month, .day], from: parsed)
            guard let month = p.month, let day = p.day else { continue }
            var comps = DateComponents(year: thisYear, month: month, day: day)
            guard var date = cal.date(from: comps) else { continue }
            // 跨年修正：解析出的日期早于今天超过一天则视为明年
            if date < cal.date(byAdding: .day, value: -1, to: now)! {
                comps.year = thisYear + 1
                guard let next = cal.date(from: comps) else { continue }
                date = next
            }
            let df = cal.dateComponents([.year, .month, .day], from: date)
            let key = String(format: "%04d%02d%02d", df.year ?? 0, df.month ?? 0, df.day ?? 0)
            out.append(DayForecast(
                dateKey: key, date: date,
                highC: Int(f["fc"] as? String ?? "") ?? 0,
                lowC: Int(f["fd"] as? String ?? "") ?? 0,
                dayWeatherCode: stripCode(f["fa"] as? String ?? ""),
                nightWeatherCode: stripCode(f["fb"] as? String ?? ""),
                windDirecCode: (f["fe"] as? String) ?? "",
                windPower: (f["fg"] as? String) ?? "",
                precipProb: nil))
        }
        return out
    }

    static func parseAlerts(_ alarm: [String: Any]?) -> [WeatherAlert] {
        guard let w = alarm?["w"] as? [[String: Any]] else { return [] }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        return w.compactMap { a in
            guard let type = a["w5"] as? String, let level = a["w7"] as? String else { return nil }
            return WeatherAlert(title: "\(type)\(level)预警",
                                text: (a["w9"] as? String) ?? "",
                                issuedAt: fmt.date(from: (a["w8"] as? String) ?? ""))
        }
    }

    /// "d07"/"n02"/"d7" → "07"/"02"/"07"
    static func stripCode(_ s: String) -> String {
        guard let first = s.first, first == "d" || first == "n" else { return s }
        let rest = String(s.dropFirst())
        return rest.count == 1 ? "0" + rest : rest
    }

    // MARK: 官方 · MPF 分钟级短临（times/values 平行数组，逐 6 分钟）

    private func fetchOfficialMinute(lat: Double, lon: Double) async throws -> MinuteForecast {
        let url = "http://mpf.weather.com.cn/mpf_v3/webgis/minute?lat=\(String(format: "%.4f", lat))&lon=\(String(format: "%.4f", lon))"
        let text = try await officialText(url: url, cityID: "")
        guard let obj = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              (obj["status"] as? String) == "true",
              let times = obj["times"] as? [String],
              let values = obj["values"] as? [Double] else {
            throw URLError(.cannotParseResponse)
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var points: [MinutePoint] = []
        for (i, t) in times.enumerated() where i < values.count {
            if let date = fmt.date(from: t) {
                points.append(MinutePoint(time: date, precipMM: values[i]))
            }
        }
        guard !points.isEmpty else { throw URLError(.cannotParseResponse) }
        return MinuteForecast(issuedAt: fmt.date(from: (obj["uptime"] as? String) ?? ""),
                              points: points, available: true, source: .official,
                              summary: obj["msg"] as? String)
    }

    // MARK: 和风 v7（可选增强）

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
        let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"

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

        var days: [DayForecast] = []
        if let d = obj["daily"] as? [String: Any],
           let times = d["time"] as? [String],
           let highs = d["temperature_2m_max"] as? [Double],
           let lows = d["temperature_2m_min"] as? [Double],
           let codes = d["weather_code"] as? [Double] {
            for i in 0..<min(times.count, 5) {
                guard let date = dayFmt.date(from: times[i]) else { continue }
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

    // MARK: 城市搜索（中国天气网官方 toy1，JSONP ref 串格式）

    struct SearchCity: Identifiable, Hashable {
        var id: String { cityID }
        let cityID: String
        let name: String
        let city: String
        let province: String
    }

    func searchCities(keyword: String) async throws -> [SearchCity] {
        let kw = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let text = try await officialText(url: "https://toy1.weather.com.cn/search?cityname=\(kw)&type=1&_=\(Int(Date().timeIntervalSince1970))",
                                          cityID: "")
        let vars = parseJSVars(text)
        // toy1 返回 ([{...}])：parseJSVars 会把整个数组存为 "" 键；兜底直接找数组
        var arr = (vars[""] as? [[String: Any]])
        if arr == nil {
            if let s = text.range(of: "["), let e = text.range(of: "]", range: s.upperBound..<text.endIndex) {
                let jsonStr = String(text[s.lowerBound...e.lowerBound])
                arr = (try? JSONSerialization.jsonObject(with: Data(jsonStr.utf8))) as? [[String: Any]]
            }
        }
        guard let list = arr else { return [] }
        return list.compactMap { item in
            guard let ref = item["ref"] as? String else { return nil }
            let f = ref.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 5, !f[0].isEmpty else { return nil }
            return SearchCity(cityID: f[0], name: f[2], city: f[4], province: f.last ?? "")
        }
    }
}
