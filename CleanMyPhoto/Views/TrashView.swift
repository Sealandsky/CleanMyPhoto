import SwiftUI

struct TrashView: View {
    @ObservedObject var photoManager: PhotoManager
    @EnvironmentObject var membershipManager: MembershipManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingDeleteConfirmation = false
    @State private var showingRestoreConfirmation = false
    @State private var showMembershipPaywall = false
    @Environment(GridSettings.self) private var gridSettings
    @State private var selectionManager = SelectionManager()

    private var trashedPhotos: [PhotoAsset] { photoManager.getTrashedAssets() }

    var body: some View {
        NavigationView {
            Group {
                if photoManager.trashCount == 0 {
                    emptyTrashView
                } else {
                    trashContent
                }
            }
            .navigationTitle(selectionManager.isSelectMode ? String(localized: "\(selectionManager.count) Selected") : String(localized: "Trash Bin"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if selectionManager.isSelectMode {
                        Button(String(localized: "Cancel")) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectionManager.clearSelection()
                            }
                        }
                    } else {
                        Button(String(localized: "Close")) {
                            dismiss()
                        }
                    }
                }

                if selectionManager.isSelectMode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            for id in selectionManager.selectedIDs {
                                photoManager.restoreFromTrash(id)
                            }
                            selectionManager.clearSelection()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward")
                                Text(String(localized: "Restore"))
                            }
                        }
                        .tint(.green)
                        .disabled(selectionManager.isEmpty)
                    }
                } else if photoManager.trashCount > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(String(localized: "Restore All")) {
                            showingRestoreConfirmation = true
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button(String(localized: "Empty All")) {
                            guard !membershipManager.isTrialExpired || membershipManager.isPremiumMember else {
                                showMembershipPaywall = true
                                return
                            }
                            showingDeleteConfirmation = true
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .confirmationDialog(String(localized: "Restore All Photos"), isPresented: $showingRestoreConfirmation) {
                Button(String(localized: "Cancel"), role: .cancel) { }
                Button(String(localized: "Restore All")) {
                    withAnimation {
                        photoManager.restoreAllFromTrash()
                        dismiss()
                    }
                }
            } message: {
                Text(String(localized: "Restore \(photoManager.trashCount) photo(s) to the main list?"))
            }
            .alert(String(localized: "Delete All Photos"), isPresented: $showingDeleteConfirmation) {
                Button(String(localized: "Cancel"), role: .cancel) { }
                Button(String(localized: "Delete"), role: .destructive) {
                    Task {
                        await photoManager.emptyTrash()
                        dismiss()
                    }
                }
            } message: {
                Text(String(localized: "Are you sure you want to permanently delete \(photoManager.trashCount) photo(s)? This action cannot be undone."))
            }
            .sheet(isPresented: $showMembershipPaywall) {
                MembershipView(isMandatory: true)
            }
            .animation(.easeInOut(duration: 0.2), value: selectionManager.isSelectMode)
        }
    }

    // MARK: - Empty State
    private var emptyTrashView: some View {
        VStack(spacing: 20) {
            Image(systemName: "trash")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text(String(localized: "Trash is Empty"))
                .font(.title2)
                .fontWeight(.semibold)

            Text(String(localized: "Photos you swipe up to delete will appear here."))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Trash Content
    private var trashContent: some View {
        ScrollView {
            LazyVGrid(columns: GridColumnHelper.columns(count: gridSettings.columnCount), spacing: GridColumnHelper.spacing) {
                ForEach(trashedPhotos) { photo in
                    PhotoCell(
                        photo: photo,
                        isSelected: selectionManager.isSelected(photo.id),
                        isSelectMode: selectionManager.isSelectMode
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectionManager.isSelectMode {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectionManager.toggle(photo.id)
                            }
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.3) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectionManager.toggle(photo.id)
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            withAnimation {
                                photoManager.restoreFromTrash(photo.id)
                            }
                        } label: {
                            Label(String(localized: "Restore"), systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    TrashView(photoManager: PhotoManager())
}
