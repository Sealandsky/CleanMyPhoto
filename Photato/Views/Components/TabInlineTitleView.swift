import SwiftUI

/// Tab 首页通用左侧大标题视图与修饰器：
/// 在 inline 导航栏模式下，于左侧呈现 26pt 粗体圆角大标题，并清空隐藏中间系统默认居中标题，
/// 保持原生自适应毛玻璃效果与极简纯箭头返回模式。
struct TabInlineTitleView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .foregroundColor(.primary)
    }
}

extension View {
    /// 为 Tab 首页配置左侧大标题的 Inline 导航栏规范
    func tabInlineNavigationTitle(_ title: String) -> some View {
        self
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    TabInlineTitleView(title: title)
                }
                ToolbarItem(placement: .principal) {
                    EmptyView()
                }
            }
    }
}
