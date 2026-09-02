import SwiftUI
import UIKit

// MARK: - Share Sheet Presenter
/// 唤起原生系统分享面板（UIActivityViewController）。
///
/// 呈现方式：取 key window 的最顶层 ViewController 直接 present——
/// UIKit 呈现保证面板以系统标准形态从屏幕底部弹出；
/// detents 设为 medium（默认半屏）/ large（上滑展开），并显示顶部拖动条。
struct ShareSheetPresenter {
    /// 弹出系统分享面板
    /// - Parameters:
    ///   - items: 分享内容（如 UIImage）
    ///   - onCompletion: 完成回调，已派发回主线程
    ///     （completed=true 分享成功；false 为用户取消；error 非空为系统分享错误）
    /// - Returns: 是否成功发起呈现（找不到呈现上下文 / 无分享内容时返回 false，
    ///   调用方可据此做静默兜底）
    @discardableResult
    static func present(items: [Any], onCompletion: @escaping (_ completed: Bool, _ error: Error?) -> Void) -> Bool {
        // 边界：无分享内容时静默返回
        guard !items.isEmpty else { return false }

        // 取前台 scene 的 key window，再下沉到最顶层 presented ViewController，
        // 保证分享面板盖在当前所有弹层之上
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let rootVC = scene.keyWindow?.rootViewController else { return false }

        var top = rootVC
        while let presented = top.presentedViewController {
            top = presented
        }

        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)

        // 底部弹出 + 高度可控：medium 默认半屏、large 上滑展开
        controller.sheetPresentationController?.detents = [.medium(), .large()]
        controller.sheetPresentationController?.prefersGrabberVisible = true
        // iPad 兜底：提供 popover 锚点，避免缺少 sourceView 崩溃
        controller.popoverPresentationController?.sourceView = top.view
        controller.popoverPresentationController?.sourceRect = CGRect(
            x: top.view.bounds.midX,
            y: top.view.bounds.maxY,
            width: 0,
            height: 0
        )

        controller.completionWithItemsHandler = { _, completed, _, error in
            DispatchQueue.main.async {
                onCompletion(completed, error)
            }
        }

        top.present(controller, animated: true)
        return true
    }
}
