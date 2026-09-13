import SwiftUI

/// 待处理照片入口按钮（各页面统一共用）：垃圾桶图标 + 数量文本，
/// 无待处理照片时仅显示图标。点击弹出待处理照片面板。
struct PendingPhotosEntryButton: View {
    @EnvironmentObject var photoManager: PhotoManager

    var body: some View {
        Button {
            photoManager.showTrash = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "trash")
                if photoManager.trashCount > 0 {
                    Text("\(photoManager.trashCount)")
                        .monospacedDigit()
                }
            }
            .font(.system(size: 15, weight: .medium, design: .rounded))
        }
    }
}

#Preview {
    PendingPhotosEntryButton()
        .environmentObject(PhotoManager())
}
