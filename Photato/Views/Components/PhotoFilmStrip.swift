import SwiftUI
import Photos

// MARK: - Photo Film Strip
/// 详情页大图下方的缩略图条：水平滚动展示当前批次全部素材，
/// 当前项高亮描边并自动居中；点击缩略图直接跳转对应素材
/// （宿主写入 currentPhotoID，DraggablePhotoView 已有的
/// onChange(of: currentPhotoID) 机制同步 localIndex 完成切换）。
struct PhotoFilmStrip: View {
    let photos: [PhotoAsset]
    let currentPhotoID: String
    var onSelect: (PhotoAsset) -> Void

    /// 缩略图统一基准高度（参考 iOS 原生相册底部底片高度）
    static let thumbHeight: CGFloat = 38
    /// 缩略图条间距（原生相册紧凑胶卷风格）
    static let itemSpacing: CGFloat = 2.5
    /// 垂直边距（上下各 7pt）
    static let verticalPadding: CGFloat = 7

    /// 布局总高度（38pt 缩略图 + 上下边距 14pt）：
    /// 供详情页动态计算大图区高度时引用，与实际渲染高度保持同步
    static let layoutHeight: CGFloat = thumbHeight + verticalPadding * 2

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Self.itemSpacing) {
                    ForEach(photos) { photo in
                        stripCell(photo)
                            .id(photo.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, Self.verticalPadding)
            }
            .frame(height: Self.layoutHeight)
            // 翻页/删除/点击跳转等任何当前素材变化：平滑滚动让其居中
            .onChange(of: currentPhotoID) { _, newID in
                guard !newID.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
            .onAppear {
                // 首帧直接定位（无动画），避免从首张滚过来的长距离动画
                guard !currentPhotoID.isEmpty else { return }
                DispatchQueue.main.async {
                    withTransaction(Transaction(animation: nil)) {
                        proxy.scrollTo(currentPhotoID, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Sizing

    /// 单个缩略图宽度：参考系统相册，按照片真实原始宽高比（pixelAspectRatio）动态计算。
    /// 钳制在 [0.45, 2.5] 之间，常规照片（3:4 竖拍、4:3 横拍、16:9、9:16等）完全按原比例，极端全景仅轻度限制。
    private func itemWidth(for photo: PhotoAsset) -> CGFloat {
        let ratio = photo.pixelAspectRatio
        let clampedRatio = min(max(ratio, 0.45), 2.5)
        return (Self.thumbHeight * clampedRatio).rounded()
    }

    /// 缩略图请求尺寸：按目标宽高的 3x 像素请求，兼顾清晰度与内存/解码速度
    private func targetSize(for width: CGFloat) -> CGSize {
        CGSize(
            width: max(60, (width * 3).rounded()),
            height: (Self.thumbHeight * 3).rounded()
        )
    }

    // MARK: - Cell

    /// 单个缩略图：根据照片原始比例动态自适应宽 + 当前项外边距呼吸感与描边高亮
    private func stripCell(_ photo: PhotoAsset) -> some View {
        let isCurrent = photo.id == currentPhotoID
        let width = itemWidth(for: photo)

        return Button {
            onSelect(photo)
        } label: {
            AssetImage(
                asset: photo.asset,
                targetSize: targetSize(for: width),
                contentMode: .fill
            )
            .frame(width: width, height: Self.thumbHeight)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                mediaBadge(photo)
            }
            // 当前项高亮描边：贴合 4pt 圆角的精致 2pt 主色描边
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(isCurrent ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            // 参考系统相册：当前选中项两侧预留额外的呼吸间距，在紧凑底片中自然凸显
            .padding(.horizontal, isCurrent ? 7 : 0)
            .opacity(isCurrent ? 1.0 : 0.88)
            .scaleEffect(isCurrent ? 1.04 : 1.0)
            .animation(.easeInOut(duration: 0.18), value: isCurrent)
        }
        .buttonStyle(.plain)
    }

    /// 视频/LivePhoto 角标：小尺寸半透明底衬托，白字保证任意缩略图上可读
    @ViewBuilder
    private func mediaBadge(_ photo: PhotoAsset) -> some View {
        let symbolName: String? = photo.mediaType == .video
            ? "play.fill"
            : (photo.mediaType == .livePhoto ? "livephoto" : nil)
        if let symbolName {
            Image(systemName: symbolName)
                .font(.system(size: 7, weight: .semibold))
                .foregroundColor(.white)
                .padding(2.5)
                .background(Color.black.opacity(0.5), in: Circle())
                .padding(2)
        }
    }
}
