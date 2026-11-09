import SwiftUI
import Photos

// MARK: - 画布照片布局元数据
struct CanvasPhotoLayout: Identifiable, Equatable {
    let id: String
    let photo: PhotoAsset
    let position: CGPoint
    let size: CGSize
    let rotationAngle: Angle
    let seed: Int

    static func == (lhs: CanvasPhotoLayout, rhs: CanvasPhotoLayout) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 确定性散落布局计算器 (Deterministic Archimedean Spiral)
final class FreeformCanvasLayoutEngine {
    /// 核心算法：以 (0, 0) 为世界坐标原点，沿阿基米德螺旋线寻找第一个不与已有卡片重叠的位置
    static func generateLayout(
        photos: [PhotoAsset],
        canvasSize: CGSize = .zero
    ) -> [CanvasPhotoLayout] {
        var placedRects: [CGRect] = []
        var results: [CanvasPhotoLayout] = []

        // 以 (0, 0) 为中心
        let center = CGPoint.zero
        let safetyPadding: CGFloat = 20.0 // 卡片之间的安全空隙，确保绝对不贴死或重叠

        for (index, photo) in photos.enumerated() {
            // 1. 确定性随机数（基于 photo.id 哈希，退出重进完全一致）
            let hashVal = abs(photo.id.hashValue)
            let tierRandom = hashVal % 100

            let baseWidth: CGFloat
            if tierRandom < 25 {
                baseWidth = 190 // 25% Hero 大图
            } else if tierRandom < 75 {
                baseWidth = 160 // 50% 标准款
            } else {
                baseWidth = 135 // 25% 紧凑款
            }

            // 保持原本宽高比（限制在 0.75 ~ 1.35 之间避免极度狭长）
            let rawRatio = CGFloat(photo.asset.pixelHeight) / CGFloat(max(1, photo.asset.pixelWidth))
            let ratio = max(0.75, min(1.35, rawRatio.isNaN || rawRatio.isZero ? 1.0 : rawRatio))
            let cardSize = CGSize(width: baseWidth, height: baseWidth * ratio + 32) // +32 为拍立得底部白色留白区

            // 随机倾斜角：-6.5° 到 +6.5°
            let angleDeg = Double((hashVal % 130) - 65) / 10.0
            let angle = Angle(degrees: angleDeg)

            // 2. 阿基米德螺旋搜索碰撞：r = b * theta
            var theta: CGFloat = CGFloat(index) * 1.6
            var foundPos = center
            var collision = true
            var attempts = 0

            while collision && attempts < 300 {
                let r: CGFloat = (attempts == 0 && index == 0) ? 0.0 : (32.0 * sqrt(CGFloat(attempts) + 1.0))
                let x = center.x + r * cos(theta)
                let y = center.y + r * sin(theta)

                // 碰撞检测外接矩形（带安全边距）
                let candidateRect = CGRect(
                    x: x - (cardSize.width + safetyPadding) / 2,
                    y: y - (cardSize.height + safetyPadding) / 2,
                    width: cardSize.width + safetyPadding,
                    height: cardSize.height + safetyPadding
                )

                // 检查是否与所有已放置卡片发生几何相交
                collision = placedRects.contains { $0.intersects(candidateRect) }
                if !collision {
                    foundPos = CGPoint(x: x, y: y)
                    placedRects.append(candidateRect)
                } else {
                    theta += 0.42
                    attempts += 1
                }
            }

            results.append(
                CanvasPhotoLayout(
                    id: photo.id,
                    photo: photo,
                    position: foundPos,
                    size: cardSize,
                    rotationAngle: angle,
                    seed: hashVal
                )
            )
        }

        return results
    }
}
