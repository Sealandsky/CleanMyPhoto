

import SwiftUI

enum AppTab: String, CaseIterable {
    case photos
    case organize
    case settings

    var localizedText: String {
        switch self {
        case .photos:
            return String(localized: "Library")
        case .organize:
            return String(localized: "Organize")
        case .settings:
            return String(localized: "Settings")
        }
    }

    var systemImage: String {
        switch self {
        case .photos:
            return "photo.stack"
        case .organize:
            return "sparkles"
        case .settings:
            return "gearshape"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .photos:
            return "photo.stack.fill"
        case .organize:
            return "sparkles"
        case .settings:
            return "gearshape.fill"
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var membershipManager: MembershipManager
    @EnvironmentObject var statisticsManager: StatisticsManager

    @State private var selectedTab: AppTab = .photos
    @State private var organizeManager = PhotoOrganizeManager()
    @State private var organizePath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView()
                .tabItem {
                    Image(systemName: selectedTab == .photos ? AppTab.photos.selectedSystemImage : AppTab.photos.systemImage)
                    Text(AppTab.photos.localizedText)
                }
                .tag(AppTab.photos)

            NavigationStack(path: $organizePath) {
                OrganizeView(
                    organizeManager: organizeManager,
                    photoManager: photoManager,
                    onCategorySelect: { category in
                        organizePath.append(OrganizeDestination.categoryResults(category))
                    }
                )
                .navigationTitle(String(localized: "Organize"))
                .navigationBarTitleDisplayMode(.large)
                .navigationDestination(for: OrganizeDestination.self) { destination in
                    switch destination {
                    case .categoryResults(let category):
                        OrganizeResultsView(
                            organizeManager: organizeManager,
                            category: category,
                            photoManager: photoManager
                        )
                    }
                }
            }
            .tabItem {
                Image(systemName: AppTab.organize.systemImage)
                Text(AppTab.organize.localizedText)
            }
            .tag(AppTab.organize)

            SettingsView()
                .tabItem {
                    Image(systemName: selectedTab == .settings ? AppTab.settings.selectedSystemImage : AppTab.settings.systemImage)
                    Text(AppTab.settings.localizedText)
                }
                .tag(AppTab.settings)
        }
        .tint(.white)
    }
}

#Preview {
    MainTabView()
        .environmentObject(PhotoManager())
        .environmentObject(MembershipManager())
        .environmentObject(StatisticsManager())
        .environment(GridSettings())
}
