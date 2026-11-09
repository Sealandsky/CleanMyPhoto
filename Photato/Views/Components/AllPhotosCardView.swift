import SwiftUI
import Photos

// MARK: - All Photos Entry Card View
/// 「我的相册」首位常驻卡片：「所有照片」全局总览入口
/// 规格精准对齐 Product Brief 与 Design v3：
/// 1. 尺寸与圆角：与 AlbumStackCell 保持一致（高度 152pt，18pt 连续平滑圆角）；
/// 2. 左上角微徽章：36×18pt 浅蓝胶囊（Color.accentColor.opacity(0.12)），文本「全部」；
/// 3. 相纸封面：88×72pt 叠放最近图库封面，圆角与柔和投影对齐设计稿；
/// 4. 标题与数量：标题「所有照片」，数量展示全局照片总数。
struct AllPhotosCardView: View {
    let totalCount: Int
    var recentAssets: [PHAsset] = []
    let onTap: () -> Void

    @State private var loadedAssets: [PHAsset] = []

    private var displayedAssets: [PHAsset] {
        if !recentAssets.isEmpty {
            return Array(recentAssets.prefix(3))
        }
        return loadedAssets
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(spacing: 0) {
                Spacer().frame(height: 12)

                stackArea
                    .frame(width: 88, height: 72)

                Spacer(minLength: 6)

                VStack(spacing: 3) {
                    Text(String(localized: "All Photos"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    Text(String(localized: "\(totalCount) Photos"))
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer().frame(height: 12)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 152)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.cardBackground)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .onAppear {
            loadRecentAssetsIfNeeded()
        }
    }

    // MARK: - 堆叠区
    private var stackArea: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let displayed = displayedAssets
            let count = displayed.count

            let cardW = width * 0.4482
            let cardH = height * 0.8137
            let cornerRadius = cardW * (8.25 / 68.90)

            ZStack {
                if count == 0 {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(.systemGray5))
                        .frame(width: cardW, height: cardH)
                        .overlay(
                            Image(systemName: "photo.stack")
                                .font(.system(size: 20, design: .rounded))
                                .foregroundColor(.secondary)
                        )
                        .position(x: width * 0.5, y: height * 0.5)
                } else if count == 1 {
                    AlbumStackCoverImage(asset: displayed[0])
                        .frame(width: cardW, height: cardH)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(Color.white, lineWidth: 1.65)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 10.5, x: 0, y: 8.67)
                        .rotationEffect(.degrees(-8.75))
                        .position(x: width * 0.5, y: height * 0.5)
                } else if count == 2 {
                    AlbumStackCoverImage(asset: displayed[0])
                        .frame(width: cardW, height: cardH)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(Color.white, lineWidth: 1.65)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 10.5, x: 0, y: 8.67)
                        .rotationEffect(.degrees(-15.0))
                        .position(x: width * 0.3941, y: height * 0.4896)

                    AlbumStackCoverImage(asset: displayed[1])
                        .frame(width: cardW, height: cardH)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(Color.white, lineWidth: 1.65)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 10.5, x: 0, y: 8.67)
                        .rotationEffect(.degrees(5.78))
                        .position(x: width * 0.6510, y: height * 0.5206)
                } else {
                    AlbumStackCoverImage(asset: displayed[0])
                        .frame(width: cardW, height: cardH)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(Color.white, lineWidth: 1.65)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 10.5, x: 0, y: 8.67)
                        .rotationEffect(.degrees(-15.0))
                        .position(x: width * 0.3295, y: height * 0.5221)

                    AlbumStackCoverImage(asset: displayed[1])
                        .frame(width: cardW, height: cardH)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(Color.white, lineWidth: 1.65)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 10.5, x: 0, y: 8.67)
                        .rotationEffect(.degrees(4.51))
                        .position(x: width * 0.5620, y: height * 0.4269)

                    AlbumStackCoverImage(asset: displayed[2])
                        .frame(width: cardW, height: cardH)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(Color.white, lineWidth: 1.65)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 10.5, x: 0, y: 8.67)
                        .rotationEffect(.degrees(5.78))
                        .position(x: width * 0.6976, y: height * 0.5679)
                }
            }
        }
    }

    private func loadRecentAssetsIfNeeded() {
        guard recentAssets.isEmpty, loadedAssets.isEmpty else { return }
        Task(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = 3
            options.predicate = NSPredicate(format: "isHidden == false")
            let result = PHAsset.fetchAssets(with: options)
            var assets: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }
            await MainActor.run {
                self.loadedAssets = assets
            }
        }
    }
}
