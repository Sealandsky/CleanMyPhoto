

import SwiftUI

struct PhotoCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct PhotoCardCover<Thumbnail: View>: View {
    let thumbnail: Thumbnail
    let coverHeight: CGFloat

    init(coverHeight: CGFloat = 150, @ViewBuilder thumbnail: () -> Thumbnail) {
        self.coverHeight = coverHeight
        self.thumbnail = thumbnail()
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                thumbnail
            }
            .frame(width: geometry.size.width, height: coverHeight)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipped()
        }
        .frame(height: coverHeight)
    }
}

struct PhotoCardInfo: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
