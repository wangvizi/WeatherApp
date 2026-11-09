import Foundation

/// 内置城市列表：贵州·安顺（默认区域）、贵州·其他市州、全国主要城市
/// 城市 ID 为中央气象台（中国天气网）编码；也可通过搜索动态获取
public enum CityData {

    // MARK: 默认区域：贵州 · 安顺
    public static let defaultCity = City(id: "101260501", name: "西秀区", city: "安顺", province: "贵州",
                                         lat: 26.2467, lon: 105.9472)

    public static let anshunDistricts: [City] = [
        City(id: "101260501", name: "西秀区", city: "安顺", province: "贵州", lat: 26.2467, lon: 105.9472),
        City(id: "101260502", name: "平坝区", city: "安顺", province: "贵州", lat: 26.4050, lon: 106.2550),
        City(id: "101260503", name: "普定县", city: "安顺", province: "贵州", lat: 26.3070, lon: 105.7460),
    ]

    // MARK: 贵州 · 其他市州
    public static let guizhouOthers: [City] = [
        City(id: "101260101", name: "贵阳", city: "贵阳", province: "贵州", lat: 26.6470, lon: 106.6302),
        City(id: "101260201", name: "遵义", city: "遵义", province: "贵州", lat: 27.7258, lon: 106.9270),
        City(id: "101260601", name: "六盘水", city: "六盘水", province: "贵州", lat: 26.5920, lon: 104.8300),
        City(id: "101260701", name: "毕节", city: "毕节", province: "贵州", lat: 27.3027, lon: 105.2828),
        City(id: "101260801", name: "铜仁", city: "铜仁", province: "贵州", lat: 27.7183, lon: 109.1895),
        City(id: "101260301", name: "都匀", city: "黔南", province: "贵州", lat: 26.2580, lon: 107.5170),
        City(id: "101260401", name: "凯里", city: "黔东南", province: "贵州", lat: 26.5830, lon: 107.9830),
        City(id: "101260901", name: "兴义", city: "黔西南", province: "贵州", lat: 25.0880, lon: 104.8970),
        City(id: "101260706", name: "威宁", city: "毕节", province: "贵州", lat: 26.8570, lon: 104.2470),
        City(id: "101260710", name: "赫章", city: "毕节", province: "贵州", lat: 27.1110, lon: 104.9440),
        City(id: "101260102", name: "清镇", city: "贵阳", province: "贵州", lat: 26.5580, lon: 106.4700),
        City(id: "101260107", name: "修文", city: "贵阳", province: "贵州", lat: 26.8390, lon: 106.5870),
        City(id: "101260106", name: "开阳", city: "贵阳", province: "贵州", lat: 27.0560, lon: 106.9670),
        City(id: "101260105", name: "息烽", city: "贵阳", province: "贵州", lat: 27.0930, lon: 106.7400),
    ]

    // MARK: 全国主要城市
    public static let national: [City] = [
        City(id: "101010100", name: "北京", city: "北京", province: "北京", lat: 39.9042, lon: 116.4074),
        City(id: "101020100", name: "上海", city: "上海", province: "上海", lat: 31.2304, lon: 121.4737),
        City(id: "101030100", name: "天津", city: "天津", province: "天津", lat: 39.0842, lon: 117.2010),
        City(id: "101040100", name: "重庆", city: "重庆", province: "重庆", lat: 29.5630, lon: 106.5510),
        City(id: "101280101", name: "广州", city: "广州", province: "广东", lat: 23.1291, lon: 113.2644),
        City(id: "101280601", name: "深圳", city: "深圳", province: "广东", lat: 22.5431, lon: 114.0579),
        City(id: "101210101", name: "杭州", city: "杭州", province: "浙江", lat: 30.2741, lon: 120.1551),
        City(id: "101190101", name: "南京", city: "南京", province: "江苏", lat: 32.0603, lon: 118.7969),
        City(id: "101190401", name: "苏州", city: "苏州", province: "江苏", lat: 31.2989, lon: 120.5853),
        City(id: "101200101", name: "武汉", city: "武汉", province: "湖北", lat: 30.5928, lon: 114.3055),
        City(id: "101250101", name: "长沙", city: "长沙", province: "湖南", lat: 28.2278, lon: 112.9388),
        City(id: "101110101", name: "西安", city: "西安", province: "陕西", lat: 34.3416, lon: 108.9398),
        City(id: "101270101", name: "成都", city: "成都", province: "四川", lat: 30.5728, lon: 104.0668),
        City(id: "101290101", name: "昆明", city: "昆明", province: "云南", lat: 24.8801, lon: 102.8329),
        City(id: "101180101", name: "郑州", city: "郑州", province: "河南", lat: 34.7466, lon: 113.6254),
        City(id: "101120101", name: "济南", city: "济南", province: "山东", lat: 36.6512, lon: 117.1201),
        City(id: "101120201", name: "青岛", city: "青岛", province: "山东", lat: 36.0671, lon: 120.3826),
        City(id: "101230101", name: "福州", city: "福州", province: "福建", lat: 26.0745, lon: 119.2965),
        City(id: "101230201", name: "厦门", city: "厦门", province: "福建", lat: 24.4798, lon: 118.0894),
        City(id: "101240101", name: "南昌", city: "南昌", province: "江西", lat: 28.6820, lon: 115.8579),
        City(id: "101220101", name: "合肥", city: "合肥", province: "安徽", lat: 31.8206, lon: 117.2272),
        City(id: "101100101", name: "太原", city: "太原", province: "山西", lat: 37.8706, lon: 112.5489),
        City(id: "101090101", name: "石家庄", city: "石家庄", province: "河北", lat: 38.0428, lon: 114.5149),
        City(id: "101050101", name: "哈尔滨", city: "哈尔滨", province: "黑龙江", lat: 45.8038, lon: 126.5340),
        City(id: "101070201", name: "大连", city: "大连", province: "辽宁", lat: 38.9140, lon: 121.6186),
        City(id: "101160101", name: "兰州", city: "兰州", province: "甘肃", lat: 36.0611, lon: 103.8343),
        City(id: "101150101", name: "西宁", city: "西宁", province: "青海", lat: 36.6171, lon: 101.7782),
        City(id: "101170101", name: "银川", city: "银川", province: "宁夏", lat: 38.4872, lon: 106.2309),
        City(id: "101130101", name: "乌鲁木齐", city: "乌鲁木齐", province: "新疆", lat: 43.8256, lon: 87.6168),
        City(id: "101080101", name: "呼和浩特", city: "呼和浩特", province: "内蒙古", lat: 40.8424, lon: 111.7490),
        City(id: "101300101", name: "南宁", city: "南宁", province: "广西", lat: 22.8167, lon: 108.3698),
        City(id: "101310101", name: "海口", city: "海口", province: "海南", lat: 20.0444, lon: 110.1999),
        City(id: "101310201", name: "三亚", city: "三亚", province: "海南", lat: 18.2528, lon: 109.5119),
        City(id: "101140601", name: "拉萨", city: "拉萨", province: "西藏", lat: 29.6500, lon: 91.1409),
        City(id: "101330101", name: "中国香港", city: "香港", province: "中国香港", lat: 22.3193, lon: 114.1694),
        City(id: "101330201", name: "中国澳门", city: "澳门", province: "中国澳门", lat: 22.1987, lon: 113.5439),
    ]

    /// 按 ID 查找内置城市
    public static func find(id: String) -> City? {
        ([defaultCity] + anshunDistricts + guizhouOthers + national).first { $0.id == id }
    }
}
