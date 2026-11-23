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
    /// 核心算法：以 (0, 0) 为世界坐标原点，沿阿基米德螺旋线寻找第一个不与已有卡片及中心标题重叠的位置
    static func generateLayout(
        photos: [PhotoAsset],
        canvasSize: CGSize = .zero,
        centerExclusionSize: CGSize = CGSize(width: 300, height: 190)
    ) -> [CanvasPhotoLayout] {
        var placedRects: [CGRect] = []
        var results: [CanvasPhotoLayout] = []

        // 以 (0, 0) 为中心
        let center = CGPoint.zero
        let safetyPadding: CGFloat = 20.0 // 卡片之间的安全空隙，确保绝对不贴死或重叠

        // 预留正中心回忆标题卡片区域，使所有照片围绕中心标题螺旋环绕
        if centerExclusionSize.width > 0 && centerExclusionSize.height > 0 {
            let centerRect = CGRect(
                x: -centerExclusionSize.width / 2,
                y: -centerExclusionSize.height / 2,
                width: centerExclusionSize.width,
                height: centerExclusionSize.height
            )
            placedRects.append(centerRect)
        }

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
            let cardSize = CGSize(width: baseWidth, height: baseWidth * ratio) // 全幅等比，无底部留白

            // 随机倾斜角：-6.5° 到 +6.5°
            let angleDeg = Double((hashVal % 130) - 65) / 10.0
            let angle = Angle(degrees: angleDeg)

            // 计算卡片带倾斜角的外接几何尺寸，确保旋转后的尖角也不与标题区及邻近卡片冲突
            let rad = abs(angle.radians)
            let cosA = CGFloat(cos(rad))
            let sinA = CGFloat(sin(rad))
            let boundingWidth = cardSize.width * cosA + cardSize.height * sinA
            let boundingHeight = cardSize.width * sinA + cardSize.height * cosA

            // 2. 阿基米德螺旋搜索碰撞：围绕中心外围展开
            // 利用黄金分割角 2.39996 (137.5°) 使相邻照片在空间上均匀散射分布
            let baseTheta: CGFloat = CGFloat(index) * 2.39996
            var foundPos: CGPoint? = nil
            var attempts = 0
            let maxAttempts = 1500
            let minRadius: CGFloat = (centerExclusionSize.width > 0 && centerExclusionSize.height > 0)
                ? max(190.0, max(centerExclusionSize.width, centerExclusionSize.height) * 0.65)
                : 0.0

            while attempts < maxAttempts {
                // 阿基米德螺旋线：r 匀速平滑向外扩散，角度持续步进
                let theta = baseTheta + CGFloat(attempts) * 0.38
                let r = minRadius + CGFloat(attempts) * 4.5
                let x = center.x + r * cos(theta)
                let y = center.y + r * sin(theta)

                // 碰撞检测外接矩形（包含旋转外接框与安全边距）
                let candidateRect = CGRect(
                    x: x - (boundingWidth + safetyPadding) / 2,
                    y: y - (boundingHeight + safetyPadding) / 2,
                    width: boundingWidth + safetyPadding,
                    height: boundingHeight + safetyPadding
                )

                // 检查是否与所有已放置卡片（含中心标题保留区）发生几何相交
                if !placedRects.contains(where: { $0.intersects(candidateRect) }) {
                    foundPos = CGPoint(x: x, y: y)
                    placedRects.append(candidateRect)
                    break
                }
                attempts += 1
            }

            // 确定最终位置：若极端情况下耗尽步数，绝对禁止回退到 (0, 0) 标题区，
            // 而是沿该照片的发散方向推到已有所有元素的外包圆外。
            let finalPos: CGPoint
            if let pos = foundPos {
                finalPos = pos
            } else {
                let maxDistance = placedRects.reduce(CGFloat(300)) { maxR, rect in
                    let dist = sqrt(rect.midX * rect.midX + rect.midY * rect.midY) + max(rect.width, rect.height)
                    return max(maxR, dist)
                }
                let safeRadius = maxDistance + max(boundingWidth, boundingHeight) + safetyPadding
                let safeX = safeRadius * cos(baseTheta)
                let safeY = safeRadius * sin(baseTheta)
                finalPos = CGPoint(x: safeX, y: safeY)
                let fallbackRect = CGRect(
                    x: safeX - (boundingWidth + safetyPadding) / 2,
                    y: safeY - (boundingHeight + safetyPadding) / 2,
                    width: boundingWidth + safetyPadding,
                    height: boundingHeight + safetyPadding
                )
                placedRects.append(fallbackRect)
            }

            results.append(
                CanvasPhotoLayout(
                    id: photo.id,
                    photo: photo,
                    position: finalPos,
                    size: cardSize,
                    rotationAngle: angle,
                    seed: hashVal
                )
            )
        }

        return results
    }
}
