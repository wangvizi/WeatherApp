import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// App Group 共享存储（主 App 写入，Widget 读取）
public enum SharedStore {
    public static let appGroup = "group.cn.weatherwidget.shared"
    public static let fileName = "shared.json"

    private static var containerURL: URL? {
        #if canImport(Darwin)
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        #else
        return nil
        #endif
    }

    public static var fileURL: URL {
        if let c = containerURL { return c.appendingPathComponent(fileName) }
        // 兜底（模拟器/未配置 App Group）
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        return tmp
    }

    public static func save(_ snapshot: WeatherSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    public static func load() -> WeatherSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WeatherSnapshot.self, from: data)
    }

    /// 快照是否已过期（超过 2 小时视为过期，与二进制文案「数据可能已过期」对应）
    public static func isStale(_ s: WeatherSnapshot) -> Bool {
        Date().timeIntervalSince(s.fetchedAt) > 2 * 3600
    }

    #if canImport(WidgetKit)
    /// 主 App 刷新完数据后重载 Widget
    public static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
    #endif
}
