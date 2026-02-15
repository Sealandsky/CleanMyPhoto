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

    var body: some Scene {
        WindowGroup {
            if hasShownWelcome {
                ContentView()
            } else {
                WelcomePage()
            }
        }
    }
}
