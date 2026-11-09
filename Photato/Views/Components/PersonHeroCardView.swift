import SwiftUI
import Photos

// MARK: - Design Metrics & Color Tokens
enum PeopleCardMetrics {
    static let cardWidth: CGFloat = 240
    static let cardHeight: CGFloat = 285
    static let cornerRadius: CGFloat = 24
    static let innerPadding: CGFloat = 12
    static let spacing: CGFloat = 12
    static let photoAreaHeight: CGFloat = 208

    // Trio Template (3+ Photos)
    static let trioHeroWidth: CGFloat = 124
    static let trioSecondaryWidth: CGFloat = 88
    static let trioSecondaryHeight: CGFloat = 100

    // Dual Template (2 Photos)
    static let dualWidth: CGFloat = 106

    // Single Template (1 Photo)
    static let singleWidth: CGFloat = 172
}

extension Color {
    /// 人物卡片专属底板色（浅色暖羊皮纸 #FAF7F2，深色高级炭灰 #1C1C1E）
    static var peopleCardBackground: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
                : UIColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1.0)
        })
    }
}

// MARK: - Person Hero Card View
/// 相册首页横滑多图拼贴杂志卡片：
/// 根据人物照片量自适应 Template A (单图)、Template B (双图交错)、Template C (三图杂志款，严格对标参考图)
struct PersonHeroCardView: View {
    let person: PersonEntity
    var index: Int? = nil
    var onSelect: (() -> Void)? = nil
    var onToggleFavorite: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            onSelect?()
        } label: {
            VStack(spacing: 8) {
                // 1. 多图层次拼贴区域 (高度 208pt)
                collageArea
                    .frame(width: PeopleCardMetrics.cardWidth - PeopleCardMetrics.innerPadding * 2,
                           height: PeopleCardMetrics.photoAreaHeight)

                // 2. 底部人物信息栏 (高度 44pt)
                bottomProfileBar
                    .frame(height: 44)
            }
            .padding(PeopleCardMetrics.innerPadding)
            .frame(width: PeopleCardMetrics.cardWidth, height: PeopleCardMetrics.cardHeight)
            .background(Color.peopleCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: PeopleCardMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PeopleCardMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 5)
        }
        .buttonStyle(BouncyCardButtonStyle())
    }

    // MARK: - Collage Area Templates

    @ViewBuilder
    private var collageArea: some View {
        let photos = person.photoIDs
        if photos.count >= 3 {
            // Template C: 经典三图杂志拼贴（参考图 Adelina 款）
            trioCollage(p1: photos[0], p2: photos[1], p3: photos[2])
        } else if photos.count == 2 {
            // Template B: 双图交错
            dualCollage(p1: photos[0], p2: photos[1])
        } else if let p1 = photos.first {
            // Template A: 单图聚焦大图（参考图 Andrew 款）
            singleCollage(p1: p1)
        } else {
            emptyPlaceholder
        }
    }

    // MARK: Template C: 三图杂志款 (左主图 + 右双伴随图)
    private func trioCollage(p1: String, p2: String, p3: String) -> some View {
        HStack(spacing: 8) {
            // 左侧大主图
            CollagePhotoThumbnail(
                assetID: p1,
                width: PeopleCardMetrics.trioHeroWidth,
                height: PeopleCardMetrics.photoAreaHeight,
                cornerRadius: 16
            )
            .rotationEffect(.degrees(-1.0))
            .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 3)

            // 右侧上下伴随图
            VStack(spacing: 8) {
                CollagePhotoThumbnail(
                    assetID: p2,
                    width: PeopleCardMetrics.trioSecondaryWidth,
                    height: PeopleCardMetrics.trioSecondaryHeight,
                    cornerRadius: 14
                )
                .rotationEffect(.degrees(1.5))
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)

                CollagePhotoThumbnail(
                    assetID: p3,
                    width: PeopleCardMetrics.trioSecondaryWidth,
                    height: PeopleCardMetrics.trioSecondaryHeight,
                    cornerRadius: 14
                )
                .rotationEffect(.degrees(-0.8))
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
            }
        }
    }

    // MARK: Template B: 双图交错
    private func dualCollage(p1: String, p2: String) -> some View {
        HStack(spacing: 8) {
            CollagePhotoThumbnail(
                assetID: p1,
                width: PeopleCardMetrics.dualWidth,
                height: PeopleCardMetrics.photoAreaHeight,
                cornerRadius: 16
            )
            .rotationEffect(.degrees(-1.5))
            .shadow(color: Color.black.opacity(0.08), radius: 5, x: 0, y: 3)

            CollagePhotoThumbnail(
                assetID: p2,
                width: PeopleCardMetrics.dualWidth,
                height: PeopleCardMetrics.photoAreaHeight,
                cornerRadius: 16
            )
            .rotationEffect(.degrees(1.5))
            .shadow(color: Color.black.opacity(0.08), radius: 5, x: 0, y: 3)
        }
    }

    // MARK: Template A: 单图聚焦
    private func singleCollage(p1: String) -> some View {
        CollagePhotoThumbnail(
            assetID: p1,
            width: PeopleCardMetrics.singleWidth,
            height: PeopleCardMetrics.photoAreaHeight,
            cornerRadius: 18
        )
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 4)
    }

    private var emptyPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.primary.opacity(0.05))
            .frame(height: PeopleCardMetrics.photoAreaHeight)
            .overlay(
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            )
    }

    // MARK: - Bottom Profile Info Bar
    private var bottomProfileBar: some View {
        HStack(spacing: 8) {
            // 人脸圆形微缩头像
            PersonAvatarView(
                assetID: person.avatarAssetID,
                faceCropRect: person.faceCropRect,
                size: 34,
                showBorder: true
            )

            // 姓名与照片数量
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName(index: index))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(photoCountText)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // 喜爱/置顶心形按钮
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onToggleFavorite?()
            } label: {
                Image(systemName: person.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(person.isFavorite ? Color(red: 1.0, green: 0.23, blue: 0.19) : Color.secondary.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 微小导航箭头指示
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary.opacity(0.5))
        }
    }

    private var photoCountText: String {
        let count = person.photoCount
        return String(format: String(localized: "%lld Photos"), Int64(count))
    }
}

// MARK: - Collage Photo Thumbnail
private struct CollagePhotoThumbnail: View {
    let assetID: String
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [Color.primary.opacity(0.06), Color.primary.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: width, height: height)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary.opacity(0.4))
                )
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: assetID) {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetch.firstObject else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = false
        options.resizeMode = .fast

        let targetSize = CGSize(width: width * 2, height: height * 2)
        PHCachingImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result = result {
                self.image = result
            }
        }
    }
}

// MARK: - Bouncy Card Button Style
private struct BouncyCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
