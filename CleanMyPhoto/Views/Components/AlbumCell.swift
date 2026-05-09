
import SwiftUI
import Photos

struct AlbumCell: View {
    let album: AlbumModel

    var body: some View {
        PhotoCard {
            PhotoCardCover {
                if let coverAsset = album.coverAsset {
                    CachedAlbumCoverView(
                        albumID: album.id,
                        coverAsset: coverAsset,
                        targetSize: CGSize(width: 400, height: 400)
                    )
                    .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                        )
                }
            }

            PhotoCardInfo(
                title: album.title,
                subtitle: "\(album.assetCount) \(String(localized: "photos"))"
            )
        }
    }
}
