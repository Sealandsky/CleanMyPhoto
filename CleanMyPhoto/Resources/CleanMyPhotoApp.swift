//
//  CleanMyPhotoApp.swift
//  CleanMyPhoto
//
//  Created by 陈嘉华 on 2026/2/7.
//

import SwiftUI

@main
struct CleanMyPhotoApp: App {
    @AppStorage("hasShownWelcome") private var hasShownWelcome: Bool = false
    @AppStorage("hasShownMembership") private var hasShownMembership: Bool = false

    @StateObject private var statisticsManager = StatisticsManager()
    @StateObject private var photoManager: PhotoManager
    @StateObject private var membershipManager = MembershipManager()

    init() {
        let stats = StatisticsManager()
        _statisticsManager = StateObject(wrappedValue: stats)
        _photoManager = StateObject(wrappedValue: PhotoManager(statisticsManager: stats))
        _membershipManager = StateObject(wrappedValue: MembershipManager())
    }

    var body: some Scene {
        WindowGroup {
            if !hasShownWelcome {
                WelcomePage()
            } else if !hasShownMembership {
                MembershipView(isMandatory: false)
                    .environmentObject(membershipManager)
            } else {
                MainTabView()
                    .environmentObject(photoManager)
                    .environmentObject(membershipManager)
                    .environmentObject(statisticsManager)
            }
        }
    }
}
