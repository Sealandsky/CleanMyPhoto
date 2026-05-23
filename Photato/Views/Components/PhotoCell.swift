import SwiftUI
import Photos

struct PhotoCell: View {
    let photo: PhotoAsset
    var isSelected: Bool = false
    var isSelectMode: Bool = false
    @Environment(GridSettings.self) private var gridSettings
    @State private var imageLoaded = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                AssetImage(
                    asset: photo.asset,
                    targetSize: CGSize(width: 400, height: 400),
                    contentMode: .fill,
                    onLoad: { imageLoaded = true }
                )
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                mediaBadge
                    .opacity(imageLoaded ? 1 : 0)

                if isSelectMode && !isSelected {
                    Color.black.opacity(0.2)
                }
            }
            .overlay(alignment: .topLeading) {
                if isSelectMode {
                    selectionIndicator
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !isSelectMode && photo.isFavorite {
                    favoriteBadge
                        .opacity(imageLoaded ? 1 : 0)
                }
            }
        }
        .aspectRatio(gridSettings.aspectRatio, contentMode: .fit)
        .animation(.easeIn(duration: 0.2), value: imageLoaded)
    }

    private var selectionIndicator: some View {
        Group {
            if isSelected {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 28, height: 28)
                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26, design: .rounded))
                        .foregroundColor(.blue)
                }
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 26, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
            }
        }
        .padding(6)
    }

    @ViewBuilder
    private var mediaBadge: some View {
        switch photo.mediaType {
        case .video:
            videoBadge
        case .livePhoto:
            livePhotoBadge
        case .gif:
            textBadge("GIF", .purple)
        case .screenshot:
            textBadge(String(localized: "SS"), .orange)
        case .image:
            EmptyView()
        }
    }

    private var videoBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "play.fill")
                .font(.system(size: 10, design: .rounded))
            if let duration = photo.videoDuration {
                Text(duration)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(6)
    }

    private var favoriteBadge: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 12, design: .rounded))
            .foregroundColor(.white)
            .padding(6)
    }

    private var livePhotoBadge: some View {
        Image(systemName: "livephoto")
            .font(.system(size: 14, design: .rounded))
            .foregroundColor(.white)
            .padding(2)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(6)
    }

    private func iconBadge(_ iconName: String, _ color: Color) -> some View {
        Image(systemName: iconName)
            .font(.system(size: 16, design: .rounded))
            .foregroundColor(.white)
            .padding(7)
            .background(color, in: RoundedRectangle(cornerRadius: 8))
            .padding(6)
    }

    private func textBadge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(color, in: RoundedRectangle(cornerRadius: 8))
            .padding(6)
    }
}

#Preview {
    PhotoCell(photo: PhotoAsset(asset: PHAsset()))
        .environment(GridSettings())
}
