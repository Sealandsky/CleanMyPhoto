import SwiftUI

extension ShapeStyle where Self == LinearGradient {
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0, green: 0.52, blue: 1.0), Color(red: 0, green: 0.72, blue: 1.0)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
