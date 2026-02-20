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

    var body: some Scene {
        WindowGroup {
            if !hasShownWelcome {
                WelcomePage()
            } else if !hasShownMembership {
                MembershipView(isMandatory: false)
            } else {
                ContentView()
            }
        }
    }
}
