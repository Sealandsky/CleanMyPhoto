import CoreLocation
import Photos

// MARK: - Photo Caption Resolver
/// 详情页标题信息解析：拍摄日期/时间格式化 + 反地理编码地址（带缓存）。
///
/// - 日期/时间来自 PHAsset.creationDate，同步可读
/// - 地址来自 asset.location 经 CLGeocoder 反地理编码，异步且系统限频，
///   因此按 localIdentifier 缓存结果（含"查询过但无结果"的负缓存，
///   避免快速切换图片时重复请求触发 CLGeocoder 限频错误）
/// - 地址提供两种粒度（对齐苹果相册）：
///   · 精简地名（导航栏标题用）：POI > 街道 > 小区/村 > 区县 > 城市 > 省
///   · 完整地址（信息面板用）：行政区划 + 街道 + POI 逐级拼装
@MainActor
final class PhotoCaptionResolver {
    static let shared = PhotoCaptionResolver()

    private let geocoder = CLGeocoder()
    /// 地址缓存：localIdentifier → (精简地名, 完整地址)；nil 表示已查询且无地址（负缓存）
    private var addressCache: [String: (place: String?, full: String?)] = [:]

    private init() {}

    // MARK: - 拍摄日期 / 时间

    /// 拍摄日期（如"2026年8月29日"）；拍摄时间元数据缺失时返回 nil，
    /// 由调用方决定置空兜底（不渲染"未知日期"类占位文案）
    func shootingDate(of asset: PHAsset) -> String? {
        guard let date = asset.creationDate else { return nil }
        return date.formatted(date: .long, time: .omitted)
    }

    /// 拍摄时间（如"14:30"）；拍摄时间元数据缺失时返回 nil
    func shootingTime(of asset: PHAsset) -> String? {
        guard let date = asset.creationDate else { return nil }
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - 地理位置地址

    /// 同步查询已缓存的精简地名（含负缓存），用于即时渲染避免闪烁
    func cachedAddress(of asset: PHAsset) -> (isCached: Bool, address: String?) {
        if let entry = addressCache[asset.localIdentifier] {
            return (true, entry.place)
        }
        return (false, nil)
    }

    /// 同步查询已缓存的完整地址（信息面板用）
    func cachedFullAddress(of asset: PHAsset) -> String? {
        addressCache[asset.localIdentifier]?.full
    }

    /// 异步解析精简地名（导航栏标题用，反向地理编码）。
    /// completion 在主线程回调：有地名传地名；无 GPS / 编码失败调用 nil，
    /// 由调用方回退到"拍摄日期"标题规则
    func resolveAddress(of asset: PHAsset, completion: @escaping @MainActor (String?) -> Void) {
        resolve(asset: asset) { entry in
            completion(entry?.place ?? nil)
        }
    }

    /// 异步解析完整地址（信息面板用）
    func resolveFullAddress(of asset: PHAsset, completion: @escaping @MainActor (String?) -> Void) {
        resolve(asset: asset) { entry in
            completion(entry?.full ?? nil)
        }
    }

    /// 统一解析入口：单次 CLGeocoder 请求，同时产出精简地名与完整地址并缓存
    private func resolve(
        asset: PHAsset,
        completion: @escaping @MainActor ((place: String?, full: String?)?) -> Void
    ) {
        let id = asset.localIdentifier

        // 命中缓存（含负缓存）直接返回，不重复请求 CLGeocoder
        if let cached = addressCache[id] {
            completion(cached)
            return
        }

        // 无 GPS 元数据：直接走无地址规则并记入负缓存
        guard let location = asset.location else {
            addressCache[id] = (nil, nil)
            completion((nil, nil))
            return
        }

        Task {
            let placemarks = try? await geocoder.reverseGeocodeLocation(location)
            let placemark = placemarks?.first
            let entry = (
                place: Self.semanticPlaceName(from: placemark),
                full: Self.fullAddress(from: placemark)
            )
            self.addressCache[id] = entry
            completion(entry)
        }
    }

    // MARK: - 语义精简地名（对齐苹果相册地点命名规则）
    /// 从一开始就选择最合适粒度的地名，而不是把完整地址做截断：
    /// 1. POI 名称优先（医院/商场/景区/学校等知名地点直接显示，不带门牌）
    /// 2. 无 POI 取最小辨识度单元：街道 → 小区/村 → 区县 → 城市
    /// 3. 反向补齐：都缺失时往上取一级行政区域（省），保证标题不为空
    static func semanticPlaceName(from placemark: CLPlacemark?) -> String? {
        guard let placemark else { return nil }

        // 1) POI 优先：CLPlacemark.name 在命中地标时即 POI 名。
        //    需排除两种"伪 POI"：
        //    · name 是街道门牌形式（"梅华东路52号"——以门牌号结尾）→ 取街道
        //    · name 恰为行政区划名 / 街道名（部分地区的 name 回填行政名）→ 走对应层级
        if let name = placemark.name, !name.isEmpty {
            let houseNumber = placemark.subThoroughfare ?? ""
            let isStreetAddressForm = !houseNumber.isEmpty && name.hasSuffix(houseNumber)
            let isAdminOrStreetName = name == placemark.locality
                || name == placemark.subLocality
                || name == placemark.subAdministrativeArea
                || name == placemark.administrativeArea
                || name == placemark.thoroughfare
            if !isStreetAddressForm && !isAdminOrStreetName {
                return name
            }
        }

        // 2) 街道（不带门牌号——subThoroughfare 刻意不参与）
        if let street = placemark.thoroughfare, !street.isEmpty {
            return street
        }

        // 3) 小区 / 村
        if let subLocality = placemark.subLocality, !subLocality.isEmpty {
            return subLocality
        }

        // 4) 区县（中国数据常在 subAdministrativeArea；与城市同名时跳过避免重复）
        if let district = placemark.subAdministrativeArea, !district.isEmpty,
           district != placemark.locality {
            return district
        }

        // 5) 城市
        if let city = placemark.locality, !city.isEmpty {
            return city
        }

        // 6) 省（反向补齐兜底）
        if let province = placemark.administrativeArea, !province.isEmpty {
            return province
        }

        return nil
    }

    // MARK: - 完整地址（信息面板用）
    /// 行政区划 + 街道 + POI 逐级拼装（省 > 市 > 区 > 街道；有 POI 时以
    /// 「POI 名, 城市」呈现，与系统信息面板的地点行一致）
    static func fullAddress(from placemark: CLPlacemark?) -> String? {
        guard let placemark else { return nil }

        if let poi = semanticPlaceName(from: placemark),
           poi != placemark.administrativeArea,
           let city = placemark.locality, !city.isEmpty, poi != city {
            // POI / 街道级地名 + 城市（如"中山大学附属第五医院, 珠海市"）
            return "\(poi), \(city)"
        }

        let parts = [
            placemark.administrativeArea,
            placemark.locality,
            placemark.subLocality,
            placemark.thoroughfare
        ].compactMap { $0 }.filter { !$0.isEmpty }
        guard !parts.isEmpty else {
            return placemark.name
        }
        return parts.joined()
    }
}
