import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repo: WeatherRepository
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("当前城市") {
                    LabeledContent("城市", value: settings.city.displayName)
                    LabeledContent("城市 ID", value: settings.effectiveCityID)
                    Button("更换城市") { dismiss(); }
                        .foregroundStyle(.tint)
                }

                Section {
                    TextField("API Host，如 h2a9cf3mhs.xy.qweatherapi.com", text: $settings.qweatherHost)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("API Key", text: $settings.qweatherKey)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("可选增强 · 和风天气（可完全留空）")
                } footer: {
                    Text("不需要填。仅在想额外补充 AQI / 更多天数时才申请。填写后官方数据仍优先，和风只补缺失字段；2026 年起须用控制台分配的独立 API Host。")
                }

                Section {
                    TextField("纬度 lat，如 26.2467", text: $settings.manualLat)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("经度 lon，如 105.9472", text: $settings.manualLon)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("中央气象台城市 ID", text: $settings.manualCityID)
                        .keyboardType(.numberPad)
                } header: {
                    Text("高级 · 手动填写坐标与城市 ID")
                } footer: {
                    Text("MPF 短临按坐标取点，实况/逐天/预警按城市 ID。切换后自动保存并刷新小组件。")
                }

                Section {
                    Toggle("使用当前位置（自动匹配城市 ID）", isOn: $settings.useCurrentLocation)
                } footer: {
                    Text("打开 App 后会自动获取一次数据")
                }

                Section {
                    Button {
                        Task {
                            await repo.refresh()
                            dismiss()
                        }
                    } label: {
                        if repo.isLoading {
                            HStack { ProgressView(); Text("正在请求中国天气网官方接口（实况 / 逐天 / 预警 / MPF 短临）…") }
                        } else {
                            Text("保存设置并立即刷新")
                        }
                    }
                    .disabled(repo.isLoading)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
