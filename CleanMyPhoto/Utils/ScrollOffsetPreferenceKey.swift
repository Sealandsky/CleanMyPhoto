//
//  ScrollOffsetPreferenceKey.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/3/30.
//

import SwiftUI

// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
