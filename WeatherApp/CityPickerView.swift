import SwiftUI

/// 城市选择：搜索全国任意城市（中国天气网官方）+ 内置城市列表 + 当前位置
struct CityPickerView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repo: WeatherRepository
    @Environment(\.dismiss) private var dismiss

    @State private var keyword = ""
    @State private var results: [WeatherRepository.SearchCity] = []
    @State private var searching = false
    @State private var searchError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        useCurrentLocation()
                    } label: {
                        Label("使用当前位置（自动匹配城市 ID）", systemImage: "location.fill")
                    }
                    if let msg = searchError {
                        Text(msg).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("搜索全国任意城市（中国天气网官方）") {
                    HStack {
                        TextField("输入城市 / 区县名，如 平坝", text: $keyword)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            .onSubmit(runSearch)
                        if searching { ProgressView() }
                        else if !keyword.isEmpty {
                            Button("搜索", action: runSearch).font(.subheadline)
                        }
                    }
                    ForEach(results) { r in
                        Button {
                            select(r)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(r.province) \(r.city) · \(r.name)")
                                Text("城市 ID \(r.cityID)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !searching, !keyword.isEmpty, results.isEmpty, searchError == nil {
                        Text("没有匹配的城市，换个关键词试试").font(.footnote).foregroundStyle(.secondary)
                    }
                    if !results.isEmpty {
                        Text("\(results.count) 条，点击即可切换").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("贵州 · 安顺（默认区域）") {
                    cityRow(CityData.defaultCity)
                    ForEach(CityData.anshunDistricts) { cityRow($0) }
                }

                Section("贵州 · 其他市州") {
                    ForEach(CityData.guizhouOthers) { cityRow($0) }
                }

                Section("全国主要城市") {
                    ForEach(CityData.national) { cityRow($0) }
                }
            }
            .navigationTitle("选择城市")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func cityRow(_ city: City) -> some View {
        Button {
            apply(city)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(city.displayName)
                    Text(String(format: "%.2f°N %.2f°E", city.lat, city.lon))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if settings.city == city {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private func apply(_ city: City) {
        settings.city = city
        settings.manualCityID = ""
        settings.useCurrentLocation = false
        Task { await repo.refresh(for: city) }  // 切换后自动保存并刷新小组件
        dismiss()
    }

    private func select(_ r: WeatherRepository.SearchCity) {
        // 搜索结果无坐标：以城市 ID 为准，坐标留空由手动/定位补充
        let city = City(id: r.cityID, name: r.name, city: r.city, province: r.province,
                        lat: settings.city.lat, lon: settings.city.lon)
        apply(city)
    }

    private func runSearch() {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return }
        searching = true
        searchError = nil
        results = []
        Task {
            do {
                results = try await repo.searchCities(keyword: kw)
            } catch {
                searchError = "搜索失败：\(error.localizedDescription)"
            }
            searching = false
        }
    }

    private func useCurrentLocation() {
        searchError = nil
        Task {
            do {
                let (lat, lon) = try await LocationResolver.shared.requestLocation()
                if let city = await LocationResolver.shared.resolveCity(lat: lat, lon: lon) {
                    settings.city = city
                    settings.useCurrentLocation = true
                    searchError = "\(city.name) 已自动匹配"
                    await repo.refresh(for: city)
                } else {
                    settings.manualLat = String(format: "%.4f", lat)
                    settings.manualLon = String(format: "%.4f", lon)
                    searchError = "坐标已更新；城市 ID 未匹配，可在城市列表中手动选"
                    await repo.refresh()
                }
            } catch {
                searchError = "定位失败：\(error.localizedDescription)；也可直接在城市列表中选择"
            }
        }
    }
}
