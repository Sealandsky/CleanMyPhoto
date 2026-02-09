//
//  TrashView.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/2/7.
//

import SwiftUI

// MARK: - Trash View
struct TrashView: View {
    @ObservedObject var photoManager: PhotoManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationView {
            Group {
                if photoManager.trashCount == 0 {
                    emptyTrashView
                } else {
                    trashGridView
                }
            }
            .navigationTitle("Trash Bin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                if photoManager.trashCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Empty All") {
                            showingDeleteConfirmation = true
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .alert("Delete All Photos", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task {
                        await photoManager.emptyTrash()
                        dismiss()
                    }
                }
            } message: {
                Text("Are you sure you want to permanently delete \(photoManager.trashCount) photo(s)? This action cannot be undone.")
            }
        }
    }

    // MARK: - Empty State
    private var emptyTrashView: some View {
        VStack(spacing: 20) {
            Image(systemName: "trash")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("Trash is Empty")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Photos you swipe up to delete will appear here.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Trash Grid
    private var trashGridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 2)
            ], spacing: 2) {
                ForEach(photoManager.getTrashedAssets()) { photo in
                    TrashPhotoCell(photo: photo)
                        .contextMenu {
                            Button(role: .destructive) {
                                withAnimation {
                                    photoManager.restoreFromTrash(photo.id)
                                }
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                        }
                }
            }
            .padding()
        }
    }
}

// MARK: - Trash Photo Cell
struct TrashPhotoCell: View {
    let photo: PhotoAsset

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Photo
                AssetImage(asset: photo.asset, targetSize: geometry.size)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .aspectRatio(contentMode: .fill)
                    .clipped()

                // Trash indicator
                Image(systemName: "trash.fill")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(8)
                    .padding(4)

                // Restore hint
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(20)
                            .padding(8)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Preview
#Preview {
    TrashView(photoManager: PhotoManager())
}
