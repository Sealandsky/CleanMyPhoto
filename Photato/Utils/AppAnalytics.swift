import Foundation
import PostHog
import SwiftUI

/// AirTraffic 埋点封装（PostHog 协议，匿名模式）。
/// 只记录"形状"：哪个界面、哪类操作、结果成败，绝不记录照片内容、文件名或用户输入。
enum AppAnalytics {
    /// 启动时调用一次。
    static func setup() {
        let config = PostHogConfig(apiKey: "ak_production_e4Z6W5XtlFs6tPGdsQaub3Sc6WMSVHI-G0kMv9BPcNs",
                                   host: "https://apps.air.build/traffic")
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false
        config.sessionReplay = false
        config.surveys = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.personProfiles = .never
        PostHogSDK.shared.setup(config)
    }

    /// 界面进入（SwiftUI 各屏幕手动上报）。
    static func screen(_ name: String) {
        PostHogSDK.shared.screen(name)
    }

    /// 自定义事件。属性只允许类别/数量/结果等形状数据。
    static func event(_ name: String, properties: [String: Any] = [:]) {
        PostHogSDK.shared.capture(name, properties: properties)
    }
}
