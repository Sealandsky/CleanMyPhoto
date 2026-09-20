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
        let membership = MembershipManager()
        _statisticsManager = StateObject(wrappedValue: stats)
        _membershipManager = StateObject(wrappedValue: membership)
        let photoManager = PhotoManager(statisticsManager: stats)
        photoManager.membershipManager = membership
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
