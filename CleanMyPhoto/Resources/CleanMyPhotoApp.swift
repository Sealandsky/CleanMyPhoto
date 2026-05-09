import SwiftUI

@main
struct CleanMyPhotoApp: App {
    @AppStorage("hasShownWelcome") private var hasShownWelcome: Bool = false
    @AppStorage("hasShownMembership") private var hasShownMembership: Bool = false

    @StateObject private var statisticsManager = StatisticsManager()
    @StateObject private var photoManager: PhotoManager
    @StateObject private var membershipManager = MembershipManager()
    @State private var gridSettings = GridSettings()

    init() {
        let stats = StatisticsManager()
        _statisticsManager = StateObject(wrappedValue: stats)
        _photoManager = StateObject(wrappedValue: PhotoManager(statisticsManager: stats))
        _membershipManager = StateObject(wrappedValue: MembershipManager())
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
                    MainTabView()
                        .environment(gridSettings)
                        .environmentObject(photoManager)
                        .environmentObject(membershipManager)
                        .environmentObject(statisticsManager)
                }
            }
            .environment(\.font, Font.system(.body, design: .rounded))
        }
    }
}
