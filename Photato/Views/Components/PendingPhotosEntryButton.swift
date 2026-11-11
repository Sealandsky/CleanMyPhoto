import SwiftUI
import Photos

// MARK: - Pending Photos Entry Button (待处理照片入口按钮)
/// 右上角通用待处理入口：
/// 1. 是否带 Liquid Glass 胶囊底由调用方 `isLiquidGlass` 决定（Tab 首页、On This Day 自由视图均带底；全屏浏览器等无底）；
/// 2. 两种形态**内容尺寸完全一致**（44pt 高、28pt 相纸堆叠、15.5pt 数字），带底时玻璃胶囊自带内边距，观感与主页入口统一；
/// 3. 空态显示原生 trash 图标，非空态显示双张倾斜相纸微缩堆叠 + 数字，新增照片实时顶替入场。
struct PendingPhotosEntryButton: View {
    @EnvironmentObject var photoManager: PhotoManager
    /// 只控制是否有 Liquid Glass 胶囊底，不再影响尺寸
    var isLiquidGlass: Bool = false

    /// 统一控件规格（v2，Bryan msg 483 真机反馈修正，Colo msg 484 定值）：
    /// 44pt 胶囊、22pt 相纸堆叠、15pt 数字、17pt 空态图标（图标:胶囊 ≈ 0.39）。
    /// 今天早些定的 38pt 在真机上偏小（真机工具栏度量比模拟器还小一截），已回 44。
    private let controlSize: CGFloat = 44
    /// 所有入口共用的内容尺寸
    private let stackFrameSize: CGFloat = 22
    private let countFontSize: CGFloat = 15
    private let contentSpacing: CGFloat = 7
    private let emptyIconSize: CGFloat = 17

    var body: some View {
        Group {
            if isLiquidGlass {
                Button {
                    photoManager.showTrash = true
                } label: {
                    sizedContent
                        .modifier(HeaderLiquidGlassModifier())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    photoManager.showTrash = true
                } label: {
                    sizedContent
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: controlSize, minHeight: controlSize)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Pending Photos"))
    }

    /// 两种形态共用的尺寸与点击区域，保证主页面与二级页看起来一样大
    /// （38pt 视觉 + 系统 ~6pt 命中裕量 ≈ 44pt 实际触控，满足 Ato 的 44pt 热区要求）
    private var sizedContent: some View {
        buttonContent
            .foregroundColor(.primary)
            .padding(.horizontal, photoManager.trashCount > 0 ? 12 : 0)
            .frame(minWidth: controlSize, minHeight: controlSize)
            .frame(width: photoManager.trashCount > 0 ? nil : controlSize, height: controlSize)
            .contentShape(Capsule())
    }

    private var buttonContent: some View {
        HStack(spacing: contentSpacing) {
            if photoManager.trashCount == 0 {
                Image(systemName: "trash")
                    .font(.system(size: emptyIconSize, weight: .regular, design: .rounded))
                    .transition(.scale.combined(with: .opacity))
            } else {
                TrashPhotoStackIcon(
                    recentPhotos: Array(photoManager.trashedAssets.suffix(2)),
                    frameSize: stackFrameSize
                )
                .transition(.scale.combined(with: .opacity))
            }

            if photoManager.trashCount > 0 {
                Text("\(photoManager.trashCount)")
                    .font(.system(size: countFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: photoManager.trashCount)
    }
}

// MARK: - Trash Photo Stack Icon (双张倾斜正方形相纸堆叠)
struct TrashPhotoStackIcon: View {
    let recentPhotos: [PhotoAsset]
    /// 相纸堆叠外接框，所有入口统一 22pt（v2 真机修正）
    var frameSize: CGFloat = 22

    private var cardSize: CGFloat { frameSize - 4 }

    var body: some View {
        ZStack {
            if recentPhotos.count >= 2 {
                // 底层照片（第二新）
                ThumbnailPolaroidCard(photo: recentPhotos[recentPhotos.count - 2], cardSize: cardSize)
                    .rotationEffect(.degrees(-8.5))
                    .offset(x: -1.5, y: 1.0)
                    .zIndex(1)
            }

            if let latest = recentPhotos.last {
                // 顶层照片（最新加入）
                ThumbnailPolaroidCard(photo: latest, cardSize: cardSize)
                    .rotationEffect(.degrees(recentPhotos.count == 1 ? -3.5 : 6.5))
                    .offset(x: recentPhotos.count == 1 ? 0 : 1.5, y: recentPhotos.count == 1 ? 0 : -0.5)
                    .id(latest.id)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .frame(width: frameSize, height: frameSize)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: recentPhotos.map(\.id))
    }
}

// MARK: - 单张正方形拍立得微缩卡片
private struct ThumbnailPolaroidCard: View {
    let photo: PhotoAsset
    let cardSize: CGFloat
    @State private var thumbnail: UIImage?

    private var targetSize: CGSize { CGSize(width: cardSize * 3, height: cardSize * 3) }

    init(photo: PhotoAsset, cardSize: CGFloat = 24) {
        self.photo = photo
        self.cardSize = cardSize
        let cached = PhotoImageCache.shared.getPlaceholder(for: photo.id) ?? PhotoImageCache.shared.get(for: photo.id, targetSize: CGSize(width: cardSize * 3, height: cardSize * 3), isHighQuality: false)
        _thumbnail = State(initialValue: cached)
    }

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
            }
        }
        .frame(width: cardSize, height: cardSize)
        .clipShape(RoundedRectangle(cornerRadius: cardSize * 0.175, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardSize * 0.175, style: .continuous)
                .strokeBorder(Color.white.opacity(0.95), lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 2, x: 0, y: 1)
        .task(id: photo.id) {
            if thumbnail == nil {
                await loadThumbnail()
            }
        }
    }

    private func loadThumbnail() async {
        if let cached = PhotoImageCache.shared.getPlaceholder(for: photo.id) ?? PhotoImageCache.shared.get(for: photo.id, targetSize: targetSize, isHighQuality: false) {
            self.thumbnail = cached
            return
        }

        let manager = PHCachingImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        manager.requestImage(for: photo.asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
            if let image {
                Task { @MainActor in
                    self.thumbnail = image
                }
            }
        }
    }
}

#Preview {
    PendingPhotosEntryButton()
        .environmentObject(PhotoManager())
}
