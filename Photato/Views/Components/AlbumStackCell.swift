import SwiftUI
import Photos

// MARK: - Album Stack Cell
/// 相簿堆叠卡片：最多 3 张白色描边长方形照片像散开的一手照片般
/// 从左到右扇形排开（彼此留有间隙，每张带投影），下方居中展示
/// 相簿名称与照片数量。
///
/// 堆叠规则（底层 → 顶层，从左到右）：
/// - 3 张：底层最小且左倾（-13°）、中层直立微右倾（+6°）、顶层最大右倾（+10°）
/// - 2 张：底层左倾（-12°）+ 顶层右倾（+10°）
/// - 1 张：单张正面居中；0 张：灰色占位卡
/// - 超过 3 张也只取最新的 3 张（数据由 AlbumModel.stackAssets 提供）
struct AlbumStackCell: View {
    let album: AlbumModel

    var body: some View {
        VStack(spacing: 10) {
            stackArea
            VStack(spacing: 2) {
                Text(album.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                // 数量沿用原 AlbumCell 的纯数字展示
                Text("\(album.assetCount)")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - 堆叠区（规格来自 Figma photo-row 635:1326）
    /// 设计稿精确布局（堆叠区 153.7×127，归一化百分比；堆叠区宽高比 1.21）：
    /// - 底层（最旧）：x 2.6%  y 5.9%   60.7% × 92.6%  左倾约 -12°
    /// - 中层：        x 31.2% y 0      50.0% × 85.3%  右倾约 +5°
    /// - 顶层（最新）：x 44.1% y 13.5%  51.4% × 86.4%  右倾约 +9°
    /// 三张互有间隙；白色描边 2.2pt + 柔和投影
    private var stackArea: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let displayed = Array(album.stackAssets.suffix(3))
            let count = displayed.count

            // 各层规格（x, y, w, h 均为堆叠区百分比；angle 为度）
            let specs: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, angle: Double)] = [
                (0.026, 0.059, 0.607, 0.926, -12),
                (0.312, 0.000, 0.500, 0.853, 5),
                (0.441, 0.135, 0.514, 0.864, 9),
            ]

            ZStack {
                if count == 0 {
                    // 空相簿占位：取中层规格的尺寸居中
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.systemGray5))
                        .frame(width: width * 0.5, height: height * 0.853)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 26, design: .rounded))
                                .foregroundColor(.secondary)
                        )
                        .offset(x: 0, y: height * 0.04)
                } else {
                    ForEach(0..<count, id: \.self) { index in
                        // 显示张数：<3 时从顶层规格反向取用，保证顶层（最新照片）始终完整呈现
                        let specIndex = count == 1 ? 2 : (count == 2 ? index + 1 : index)
                        let s = specs[specIndex]
                        // 设计稿百分比是含旋转的包围盒：卡片本体按 88% 缩放
                        // （补偿 ±12° 旋转的包围盒放大），中心对齐包围盒中心
                        let bodyW = width * s.w * 0.88
                        let bodyH = height * s.h * 0.88
                        AlbumStackCoverImage(asset: displayed[index])
                            .frame(width: bodyW, height: bodyH)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            // 白色描边 2.2：设计稿中每张照片的相纸白边
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white, lineWidth: 2.2)
                            )
                            .shadow(color: .black.opacity(0.22), radius: 7, x: 0, y: 4)
                            .rotationEffect(.degrees(s.angle))
                            .position(x: width * (s.x + s.w / 2), y: height * (s.y + s.h / 2))
                    }
                }
            }
            .frame(width: width, height: height)
        }
        .aspectRatio(153.7 / 127.0, contentMode: .fit)
    }
}

// MARK: - Stack Cover Image
/// 堆叠单张封面：按资产维度加载并做内存缓存
/// （CachedAlbumCoverView 以相簿 ID 为缓存键，无法区分同一相簿的多张堆叠图，
/// 因此这里单独按 asset.localIdentifier 缓存）
private struct AlbumStackCoverImage: View {
    let asset: PHAsset

    @State private var image: UIImage?
    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
            }
        }
        .onAppear { load() }
    }

    private func load() {
        let key = asset.localIdentifier as NSString
        if let cached = Self.cache.object(forKey: key) {
            image = cached
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 500, height: 700),
            contentMode: .aspectFill,
            options: options
        ) { img, info in
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            guard let img, !isDegraded else { return }   // 只采用最终高清帧
            Self.cache.setObject(img, forKey: key)
            image = img
        }
    }
}

#Preview("Album Stack Cell") {
    ScrollView {
        HStack(spacing: 16) {
            AlbumStackCell(album: AlbumModel(id: "p1", title: "Three", assetCount: 99))
            AlbumStackCell(album: AlbumModel(id: "p2", title: "Two", assetCount: 2))
            AlbumStackCell(album: AlbumModel(id: "p3", title: "One", assetCount: 1))
        }
        HStack(spacing: 16) {
            AlbumStackCell(album: AlbumModel(id: "p4", title: "Empty", assetCount: 0))
        }
    }
    .padding()
    .background(Color(.systemBackground))
}
