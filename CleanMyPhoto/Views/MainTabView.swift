//
//  MainTabView.swift
//  CleanMyPhoto
//

import SwiftUI

enum AppTab: String, CaseIterable {
    case photos
    case settings

    var localizedText: String {
        switch self {
        case .photos:
            return String(localized: "Library")
        case .settings:
            return String(localized: "Settings")
        }
    }

    var systemImage: String {
        switch self {
        case .photos:
            return "photo.stack"
        case .settings:
            return "gearshape"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .photos:
            return "photo.stack.fill"
        case .settings:
            return "gearshape.fill"
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var membershipManager: MembershipManager

    @State private var selectedTab: AppTab = .photos

    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView()
                .tabItem {
                    Image(systemName: selectedTab == .photos ? AppTab.photos.selectedSystemImage : AppTab.photos.systemImage)
                    Text(AppTab.photos.localizedText)
                }
                .tag(AppTab.photos)

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
}
