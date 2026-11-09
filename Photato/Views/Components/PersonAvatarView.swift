import SwiftUI
import Photos

// MARK: - Person Avatar Memory Cache
private final class FaceAvatarCache {
    static let shared = FaceAvatarCache()
    private let cache = NSCache<NSString, UIImage>()

    func get(for id: String) -> UIImage? {
        cache.object(forKey: id as NSString)
    }

    func set(_ image: UIImage, for id: String) {
        cache.setObject(image, forKey: id as NSString)
    }
}

// MARK: - Person Avatar View
/// 圆形人脸微缩头像组件：
/// 根据人脸标准归一化矩形（faceCropRect）精准聚焦裁切人脸，外加光晕与高光描边。
struct PersonAvatarView: View {
    let assetID: String
    let faceCropRect: CGRect
    var size: CGFloat = 34
    var showBorder: Bool = true

    @State private var avatarImage: UIImage?

    var body: some View {
        ZStack {
            if let image = avatarImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.45))
                            .foregroundColor(Color.accentColor.opacity(0.7))
                    )
            }
        }
        .frame(width: size, height: size)
        .overlay(
            Group {
                if showBorder {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5)
                        .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
                }
            }
        )
        .task(id: assetID) {
            loadAvatar()
        }
    }

    private func loadAvatar() {
        if let cached = FaceAvatarCache.shared.get(for: assetID) {
            self.avatarImage = cached
            return
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetchResult.firstObject else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        options.resizeMode = .fast
        options.isSynchronous = false

        // 请求稍高分辨率以供精准人脸裁切
        let pixelSize = CGSize(width: 320, height: 320)
        PHCachingImageManager.default().requestImage(
            for: asset,
            targetSize: pixelSize,
            contentMode: .aspectFill,
            options: options
        ) { fullImage, _ in
            guard let full = fullImage else { return }

            // 在后台线程执行人脸裁剪
            DispatchQueue.global(qos: .userInitiated).async {
                let cropped = self.cropToFace(image: full, unitRect: self.faceCropRect)
                DispatchQueue.main.async {
                    if let result = cropped {
                        FaceAvatarCache.shared.set(result, for: self.assetID)
                        self.avatarImage = result
                    } else {
                        FaceAvatarCache.shared.set(full, for: self.assetID)
                        self.avatarImage = full
                    }
                }
            }
        }
    }

    private func cropToFace(image: UIImage, unitRect: CGRect) -> UIImage? {
        let normalizedImage: UIImage
        if image.imageOrientation == .up {
            normalizedImage = image
        } else {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
            normalizedImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
        }
        guard let cg = normalizedImage.cgImage else { return nil }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)

        // 适当外扩 25% 留白，使得发型和面部比例更自然
        let marginX = unitRect.width * 0.25
        let marginY = unitRect.height * 0.25

        let expandedX = max(0, unitRect.origin.x - marginX)
        let expandedY = max(0, unitRect.origin.y - marginY)
        let expandedW = min(1.0 - expandedX, unitRect.width + marginX * 2)
        let expandedH = min(1.0 - expandedY, unitRect.height + marginY * 2)

        // 统一正方形取景
        let maxSide = max(expandedW, expandedH)
        let squareX = max(0, expandedX - (maxSide - expandedW) / 2)
        let squareY = max(0, expandedY - (maxSide - expandedH) / 2)
        let squareSide = min(maxSide, min(1.0 - squareX, 1.0 - squareY))

        let pixelRect = CGRect(
            x: squareX * w,
            y: squareY * h,
            width: squareSide * w,
            height: squareSide * h
        ).integral

        guard let croppedCG = cg.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: croppedCG)
    }
}
