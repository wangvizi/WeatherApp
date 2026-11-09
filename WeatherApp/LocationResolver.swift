import Foundation
import CoreLocation

/// 使用当前位置（自动匹配城市 ID）：
/// CLLocationManager 取点 → CLGeocoder 反查区县名 → toy1 搜索匹配城市 ID
@MainActor
final class LocationResolver: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationResolver()

    @Published var authorization: CLAuthorizationStatus = CLLocationManager().authorizationStatus
    @Published var statusMessage: String?

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<(Double, Double), Error>?

    func requestLocation() async throws -> (lat: Double, lon: Double) {
        manager.delegate = self
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // 等待授权回调后由用户重试
            throw CLError(.denied)
        case .denied, .restricted:
            throw CLError(.denied)
        default:
            break
        }
        return try await withCheckedThrowingContinuation { cont in
            continuation = cont
            manager.requestLocation()
        }
    }

    /// 反查坐标 → 城市（失败时保留原坐标，对应日志 "CityPicker: 坐标解析失败，保留原坐标"）
    func resolveCity(lat: Double, lon: Double) async -> City? {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: lat, longitude: lon), preferredLocale: Locale(identifier: "zh_CN"))
        guard let p = placemarks?.first else { return nil }
        let name = p.subLocality ?? p.locality ?? ""
        let province = p.administrativeArea ?? ""
        guard !name.isEmpty else { return nil }
        do {
            let matches = try await WeatherRepository.shared.searchCities(keyword: name)
            if let m = matches.first(where: { $0.name == name }) ?? matches.first {
                return City(id: m.cityID, name: m.name, city: m.city, province: province.isEmpty ? m.province : province,
                            lat: lat, lon: lon)
            }
        } catch {
            NSLog("CityPicker: 坐标解析失败，保留原坐标")
        }
        return nil
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            continuation?.resume(returning: (loc.coordinate.latitude, loc.coordinate.longitude))
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in authorization = manager.authorizationStatus }
    }
}
