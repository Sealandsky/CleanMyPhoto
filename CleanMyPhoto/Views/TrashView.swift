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
    @State private var showingRestoreConfirmation = false

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
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Restore All") {
                            showingRestoreConfirmation = true
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Empty All") {
                            showingDeleteConfirmation = true
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .confirmationDialog("Restore All Photos", isPresented: $showingRestoreConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Restore All") {
                    withAnimation {
                        photoManager.restoreAllFromTrash()
                        dismiss()
                    }
                }
            } message: {
                Text("Restore \(photoManager.trashCount) photo(s) to the main list?")
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
                    PhotoCell(photo: photo)
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
        }
    }
}

// MARK: - Preview
#Preview {
    TrashView(photoManager: PhotoManager())
}
