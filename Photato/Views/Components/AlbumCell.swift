
import SwiftUI
import Photos

struct AlbumCell: View {
    let album: AlbumModel

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let coverAsset = album.coverAsset {
                        CachedAlbumCoverView(
                            albumID: album.id,
                            coverAsset: coverAsset,
                            targetSize: CGSize(width: 300, height: 400)
                        )
                        .scaledToFill()
                    } else {
                        Rectangle().fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 30, design: .rounded))
                                    .foregroundColor(.gray)
                            )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()

                Rectangle()
                    .fill(.thickMaterial)
                     .background(Color.black.opacity(0.35))
                    .frame(height: geo.size.height * 0.8)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(maxWidth: .infinity, alignment: .bottom)

                VStack(alignment: .leading, spacing: -1) {
                    Text(album.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("\(album.assetCount)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(6)
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
        )
    }
}

#Preview {
    ScrollView {
        HStack(spacing: 12) {
            AlbumCell(album: AlbumModel(
                id: "preview-1",
                title: "Camera Roll",
                assetCount: 256
            ))
            AlbumCell(album: AlbumModel(
                id: "preview-2",
                title: "Screenshots",
                assetCount: 42
            ))
        }
        .padding(.horizontal)
    }
    .background(Color.black)
}
