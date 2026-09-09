import SwiftUI
import Photos

// MARK: - Album Stack Cell
/// 相簿堆叠卡片：根据相簿素材数量智能呈现 1 张、2 张、3 张照片的相纸叠放效果
/// 规格精准对齐 Figma 686:1312（Frame 27 组件集）：
///
/// 堆叠规则（底层 → 顶层，从左到右）：
/// - 3 张以上（Default 686:1311）：底层左倾（-15°）、中层微右倾（+4.5°）、顶层右倾（+5.8°）
/// - 2 张（Variant2 686:1313）：底层偏左（-15°）+ 顶层偏右（+5.8°），左右优美平衡
/// - 1 张（Variant3 686:1318）：单张居中微倾（-8.75°），呈现单张随手摆放的相纸自然质感
/// - 0 张：灰色居中占位卡
/// - 超过 3 张取最新的 3 张（旧→新升序，最新在最顶层）
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
                // 数量展示
                Text("\(album.assetCount)")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - 堆叠规格定义（精准对齐 Figma 686:1312 组件集）
    private struct StackLayerSpec {
        let cx: CGFloat
        let cy: CGFloat
        let angle: Double
    }

    private static func layerSpecs(for count: Int) -> [StackLayerSpec] {
        switch count {
        case 1:
            // Variant3 (Figma 686:1318)：单张精确居中，自然微倾 -8.75°
            return [
                StackLayerSpec(cx: 0.5000, cy: 0.4970, angle: -8.75)
            ]
        case 2:
            // Variant2 (Figma 686:1313)：双张照片左右展开（底层左倾 -15°，顶层右倾 +5.78°）
            return [
                StackLayerSpec(cx: 0.3941, cy: 0.4896, angle: -15.00),
                StackLayerSpec(cx: 0.6510, cy: 0.5206, angle: 5.78)
            ]
        default:
            // Default 3+ 张 (Figma 686:1311)：三张散开的一手照片
            return [
                StackLayerSpec(cx: 0.3295, cy: 0.5221, angle: -15.00),
                StackLayerSpec(cx: 0.5620, cy: 0.4269, angle: 4.51),
                StackLayerSpec(cx: 0.6976, cy: 0.5679, angle: 5.78)
            ]
        }
    }

    // MARK: - 堆叠区
    /// 设计稿精确布局（堆叠区 153.71×127，归一化百分比；堆叠区宽高比 1.21）：
    /// - 卡片未旋转物理尺寸：宽 68.90 (44.82%)，高 103.34 (81.37%)，标准 2:3 纵向相纸
    /// - 白色描边 2.2pt + 柔和投影
    private var stackArea: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let displayed = Array(album.stackAssets.suffix(3))
            let count = displayed.count

            // 卡片尺寸与圆角（对齐设计稿 68.90 × 103.34，cornerRadius 8.25）
            let cardW = width * 0.4482
            let cardH = height * 0.8137
            let cornerRadius = cardW * (8.25 / 68.90)

            ZStack {
                if count == 0 {
                    // 空相簿占位：单张卡片居中直立
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(.systemGray5))
                        .frame(width: cardW, height: cardH)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 24, design: .rounded))
                                .foregroundColor(.secondary)
                        )
                        .position(x: width * 0.5, y: height * 0.5)
                } else {
                    let specs = Self.layerSpecs(for: count)
                    ForEach(0..<count, id: \.self) { index in
                        let s = specs[index]
                        AlbumStackCoverImage(asset: displayed[index])
                            .frame(width: cardW, height: cardH)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                            // 白色相纸白边 2.2pt
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .strokeBorder(Color.white, lineWidth: 2.2)
                            )
                            // 柔和自然投影（对齐 Figma: blur 14.09, y 11.56, black 15%）
                            .shadow(color: .black.opacity(0.18), radius: 7, x: 0, y: 5)
                            .rotationEffect(.degrees(s.angle))
                            .position(x: width * s.cx, y: height * s.cy)
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
            targetSize: CGSize(width: 600, height: 800),
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
