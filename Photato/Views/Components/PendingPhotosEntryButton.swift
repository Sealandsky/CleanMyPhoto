import SwiftUI

/// 待处理照片入口按钮（各页面统一共用）：垃圾桶图标 + 数量文本，
/// 无待处理照片时仅显示图标。点击弹出待处理照片面板。
struct PendingPhotosEntryButton: View {
    @EnvironmentObject var photoManager: PhotoManager
    var isLiquidGlass: Bool = false

    var body: some View {
        if isLiquidGlass {
            Button {
                photoManager.showTrash = true
            } label: {
                buttonContent
                    .foregroundColor(.primary)
                    .padding(.horizontal, photoManager.trashCount > 0 ? 12 : 0)
                    .frame(minWidth: 44, minHeight: 44)
                    .frame(width: photoManager.trashCount > 0 ? nil : 44, height: 44)
                    .modifier(HeaderLiquidGlassModifier())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        } else {
            Button {
                photoManager.showTrash = true
            } label: {
                buttonContent
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
    }

    private var buttonContent: some View {
        HStack(spacing: 4) {
            Image(systemName: "trash")
                .font(.system(size: 24, weight: .regular, design: .rounded))
            if photoManager.trashCount > 0 {
                Text("\(photoManager.trashCount)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        }
    }
}

#Preview {
    PendingPhotosEntryButton()
        .environmentObject(PhotoManager())
}
