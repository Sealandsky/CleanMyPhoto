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

    /// 布局总高度（46pt 缩略图 + 描边外扩 6pt + 上下 padding 10pt）：
    /// 供详情页动态计算大图区高度时引用，与实际渲染高度保持同步
    static let layoutHeight: CGFloat = 62

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(photos) { photo in
                        stripCell(photo)
                            .id(photo.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
            }
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

    // MARK: - Cell

    /// 单个缩略图：48pt 方图 + 当前项外扩 2pt 主色描边；视频/LivePhoto 右下角角标
    private func stripCell(_ photo: PhotoAsset) -> some View {
        let isCurrent = photo.id == currentPhotoID

        return Button {
            onSelect(photo)
        } label: {
            AssetImage(
                asset: photo.asset,
                targetSize: CGSize(width: 112, height: 112),
                contentMode: .fill
            )
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                mediaBadge(photo)
            }
            // 描边画在图片边界外 3pt 处，外层 padding 预留同等空间防止裁切
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 2)
                    .padding(-3)
            )
            .padding(3)
            .opacity(isCurrent ? 1 : 0.55)
            .scaleEffect(isCurrent ? 1.02 : 1)
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
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white)
                .padding(3)
                .background(Color.black.opacity(0.45), in: Circle())
                .offset(x: -1, y: 1)
        }
    }
}
