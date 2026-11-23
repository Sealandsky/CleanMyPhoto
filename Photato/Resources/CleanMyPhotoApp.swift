import SwiftUI

@main
struct CleanMyPhotoApp: App {
    @AppStorage("hasShownWelcome") private var hasShownWelcome: Bool = false
    @AppStorage("hasShownMembership") private var hasShownMembership: Bool = false

    @StateObject private var statisticsManager: StatisticsManager
    @StateObject private var photoManager: PhotoManager
    @StateObject private var membershipManager: MembershipManager
    @State private var gridSettings = GridSettings()

    /// widget deep link 暂存的年份：welcome / 会员引导未完成时先存着，进入主界面后再消费
    @State private var pendingDeepLinkYear: Int?

    init() {
        AppAnalytics.setup()
        AirCrashReports.start(apiKey: "ak_production_e4Z6W5XtlFs6tPGdsQaub3Sc6WMSVHI-G0kMv9BPcNs",
                              endpoint: "https://apps.air.build/v1/ingest/crashes")
        PurchaseReporter.start()
        SoundManager.shared.preloadSounds()
        MainTabView.configureTabBarAppearance()
        // 注册后台静默刷新任务（必须在启动完成前）
        OnThisDayBackgroundScheduler.shared.register()
        // iOS 26 液态玻璃修复：移除 swizzle（详见 MainTabView.swift 顶部注释）
        let stats = StatisticsManager()
        let membership = MembershipManager()
        let photoManager = PhotoManager(statisticsManager: stats)
        photoManager.membershipManager = membership
        _statisticsManager = StateObject(wrappedValue: stats)
        _membershipManager = StateObject(wrappedValue: membership)
        _photoManager = StateObject(wrappedValue: photoManager)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasShownWelcome {
                    WelcomePage()
                } else if !hasShownMembership {
                    MembershipView(isMandatory: false)
                        .environmentObject(membershipManager)
                } else {
                    MainTabView(pendingDeepLinkYear: $pendingDeepLinkYear)
                        .environment(gridSettings)
                        .environmentObject(photoManager)
                        .environmentObject(membershipManager)
                        .environmentObject(statisticsManager)
                }
            }
            .environment(\.font, Font.system(.body, design: .rounded))
            .onOpenURL { url in
                guard url.scheme == "photato", url.host == "onthisday" else { return }
                let year = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "year" })?.value
                    .flatMap(Int.init)
                // year 为 nil 表示空态跳转：用 -1 作为哨兵，仅切到回忆 Tab 不带年份
                pendingDeepLinkYear = year ?? -1
            }
        }
    }
}
