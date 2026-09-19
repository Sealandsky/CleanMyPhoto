import SwiftUI
import Photos
import ImageIO
import CoreLocation

// MARK: - Photo Info Sheet
/// 详情页「信息」半屏面板：展示当前素材的元数据。
/// 同步项（日期时间/地点/分辨率/媒体类型/时长）首帧直出；
/// 文件大小与拍摄参数（机型/ISO/光圈/快门/焦距）异步补齐，
/// 取不到的行整体不显示（不留空行占位）。
struct PhotoInfoSheet: View {
    let photo: PhotoAsset

    @State private var fileSizeText: String?
    @State private var addressText: String?
    @State private var exifRows: [(label: String, value: String)] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // iOS 26 抓手条下方内容区自动让位，此处 padding 即与抓手条的净间距：
                // 14pt 对齐系统原生面板的标题间距
                Text(String(localized: "Info"))
                    .font(.system(.headline, design: .rounded))
                    .padding(.top, 14)
                    .padding(.bottom, 16)

                LazyVStack(spacing: 0) {
                    ForEach(Array(baseRows.enumerated()), id: \.offset) { index, row in
                        infoRow(row.label, value: row.value)
                    }
                    ForEach(Array(exifRows.enumerated()), id: \.offset) { _, row in
                        infoRow(row.label, value: row.value)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .background(Color(UIColor.systemGroupedBackground))
        .task {
            await loadAsyncInfo()
        }
    }

    // MARK: - Rows

    private func infoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.bottom, 8)
    }

    /// 同步基础信息（元数据直读，零 IO）
    private var baseRows: [(label: String, value: String)] {
        var rows: [(String, String)] = []
        let asset = photo.asset

        // 拍摄日期时间（与详情页标题同源）
        let date = PhotoCaptionResolver.shared.shootingDate(of: asset)
        let time = PhotoCaptionResolver.shared.shootingTime(of: asset)
        if let date {
            rows.append((String(localized: "Date Taken"), time.map { "\(date) \($0)" } ?? date))
        }

        // 地点：优先已解析地址，未就绪时先以经纬度垫底（异步地址完成后平滑替换）
        if let location = asset.location {
            rows.append((String(localized: "Location"), addressText ?? Self.coordinateText(location)))
        }

        // 分辨率
        if asset.pixelWidth > 0, asset.pixelHeight > 0 {
            rows.append((String(localized: "Dimensions"), "\(asset.pixelWidth) × \(asset.pixelHeight)"))
        }

        // 媒体类型 + 时长
        rows.append((String(localized: "Media Type"), mediaTypeText))
        if let duration = photo.videoDuration {
            rows.append((String(localized: "Duration"), duration))
        }

        // 文件大小（异步，未就绪时暂不占位）
        if let size = fileSizeText {
            rows.append((String(localized: "File Size"), size))
        }

        return rows
    }

    private var mediaTypeText: String {
        switch photo.mediaType {
        case .image: return String(localized: "Photo")
        case .video: return String(localized: "Video")
        case .livePhoto: return String(localized: "Live Photo")
        case .gif: return "GIF"
        case .screenshot: return String(localized: "Screenshot")
        }
    }

    // MARK: - Async Info

    /// 异步补齐：地址、文件大小与（仅图片）拍摄参数
    private func loadAsyncInfo() async {
        let asset = photo.asset

        // 1. 地址（完整地址：标题用精简地名，信息面板展示完整地点行）：
        //    命中缓存同步取，否则异步解析后回填
        if let cachedFull = PhotoCaptionResolver.shared.cachedFullAddress(of: asset) {
            if !cachedFull.isEmpty { addressText = cachedFull }
        } else {
            PhotoCaptionResolver.shared.resolveFullAddress(of: asset) { address in
                if let address, !address.isEmpty { addressText = address }
            }
        }

        // 2. 文件大小
        let size = await PHAssetSizeHelper.getAssetSize(asset)
        fileSizeText = ByteFormatter.format(size)

        // 3. 拍摄参数（仅图片；Live Photo 取静态帧）
        if asset.mediaType == .image {
            exifRows = await Self.loadExifRows(for: asset)
        }
    }

    /// 经纬度文本：±0.0000°（无地址时兜底展示，避免地点行空白）
    private static func coordinateText(_ location: CLLocation) -> String {
        let lat = String(format: "%.4f°", location.coordinate.latitude)
        let lon = String(format: "%.4f°", location.coordinate.longitude)
        return "\(lat), \(lon)"
    }

    /// 读取图片 EXIF 拍摄参数：requestImageDataAndOrientation 拿原始数据 →
    /// CIImage 属性字典；任一参数缺失则跳过该行
    private static func loadExifRows(for asset: PHAsset) async -> [(label: String, value: String)] {
        let data: Data? = await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { imageData, _, _, _ in
                continuation.resume(returning: imageData)
            }
        }
        guard let data,
              let properties = CIImage(data: data)?.properties else { return [] }

        var rows: [(String, String)] = []
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]

        if let model = (tiff?[kCGImagePropertyTIFFModel as String] as? String), !model.isEmpty {
            rows.append((String(localized: "Camera"), model))
        }
        if let fNumber = exif?[kCGImagePropertyExifFNumber as String] as? Double {
            rows.append((String(localized: "Aperture"), String(format: "ƒ/%.1f", fNumber)))
        }
        if let seconds = exif?[kCGImagePropertyExifExposureTime as String] as? Double, seconds > 0 {
            let text = seconds < 1
                ? String(format: "1/%d s", Int((1 / seconds).rounded()))
                : String(format: "%.1f s", seconds)
            rows.append((String(localized: "Shutter"), text))
        }
        if let iso = exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [Int], let first = iso.first {
            rows.append((String(localized: "ISO"), "\(first)"))
        }
        if let focal = exif?[kCGImagePropertyExifFocalLength as String] as? Double {
            rows.append((String(localized: "Focal Length"), String(format: "%.0f mm", focal)))
        }
        return rows
    }
}
