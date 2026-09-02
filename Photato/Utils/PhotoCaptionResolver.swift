import CoreLocation
import Photos

// MARK: - Photo Caption Resolver
/// 详情页标题信息解析：拍摄日期/时间格式化 + 反地理编码地址（带缓存）。
///
/// - 日期/时间来自 PHAsset.creationDate，同步可读
/// - 地址来自 asset.location 经 CLGeocoder 反地理编码，异步且系统限频，
///   因此按 localIdentifier 缓存结果（含"查询过但无结果"的负缓存，
///   避免快速切换图片时重复请求触发 CLGeocoder 限频错误）
@MainActor
final class PhotoCaptionResolver {
    static let shared = PhotoCaptionResolver()

    private let geocoder = CLGeocoder()
    /// 地址缓存：localIdentifier → 地址串；nil 表示已查询且无地址（负缓存）
    private var addressCache: [String: String?] = [:]

    private init() {}

    // MARK: - 拍摄日期 / 时间

    /// 拍摄日期（如"2026年8月29日"）；元数据缺失时返回占位文案
    func shootingDate(of asset: PHAsset) -> String {
        guard let date = asset.creationDate else {
            return String(localized: "Unknown date")
        }
        return date.formatted(date: .long, time: .omitted)
    }

    /// 拍摄时间（如"14:30"）；元数据缺失时返回占位文案
    func shootingTime(of asset: PHAsset) -> String {
        guard let date = asset.creationDate else {
            return String(localized: "Unknown time")
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - 地理位置地址

    /// 异步解析图片地址（反向地理编码）。
    /// completion 在主线程回调：有地址传地址串；无 GPS / 编码失败 / 拼装为空调用
    /// 由调用方回退到"拍摄日期"标题规则。
    func resolveAddress(of asset: PHAsset, completion: @escaping (String?) -> Void) {
        let id = asset.localIdentifier

        // 命中缓存（含负缓存）直接返回，不重复请求 CLGeocoder
        if let cached = addressCache[id] {
            completion(cached)
            return
        }

        // 无 GPS 元数据：直接走无地址规则并记入负缓存
        guard let location = asset.location else {
            addressCache[id] = .some(nil)
            completion(nil)
            return
        }

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self else { return }
            let placemark = placemarks?.first
            // 地址拼装：城市 + 街道，缺项自动跳过；
            // 拼装为空时回退行政区域（如"广东省"），仍为空则视为无地址
            let parts = [placemark?.locality, placemark?.thoroughfare].compactMap { $0 }
            var address: String? = parts.isEmpty ? nil : parts.joined(separator: " ")
            if address == nil {
                address = placemark?.administrativeArea
            }

            self.addressCache[id] = .some(address)
            DispatchQueue.main.async {
                completion(address)
            }
        }
    }
}
