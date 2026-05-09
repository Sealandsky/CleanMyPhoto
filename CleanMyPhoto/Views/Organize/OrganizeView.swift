import SwiftUI
import Photos

struct OrganizeView: View {
    @Bindable var organizeManager: PhotoOrganizeManager
    @ObservedObject var photoManager: PhotoManager
    let onCategorySelect: (OrganizeCategory) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                categoryCards

                if organizeManager.isAnalyzing {
                    progressCard
                } else if organizeManager.totalGroupCount == 0 && organizeManager.hasLoadedInitialData {
                    scanActionCard
                }
            }
            .padding(16)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .task {
            if organizeManager.totalGroupCount == 0 && !organizeManager.isAnalyzing {
                await performInitialScan()
            }
        }
        .toolbar {
            if organizeManager.isAnalyzing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Cancel")) {
                        organizeManager.cancelAnalysis()
                    }
                }
            } else if organizeManager.totalGroupCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Re-scan")) {
                        organizeManager.startFullAnalysis()
                    }
                }
            }
        }
    }

    private func performInitialScan() async {
        await organizeManager.quickAnalysis()
    }

    // MARK: - Category Cards

    private var categoryCards: some View {
        ForEach(OrganizeCategory.allCases) { category in
            categoryCard(for: category)
        }
    }

    private func categoryCard(for category: OrganizeCategory) -> some View {
        let count = organizeManager.stat(for: category)
        let hasResults = count > 0
        let identifiers = Array((organizeManager.scanResults[category] ?? [])
            .flatMap { $0.localIdentifiers }
            .prefix(3))

        return Button {
            if hasResults {
                onCategorySelect(category)
            } else {
                organizeManager.startFullAnalysis()
            }
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(hasResults ? "\(count)" : "0")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(hasResults ? .primary : .secondary)

                    Text(category.localizedText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                CategoryThumbnails(identifiers: identifiers)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .disabled(organizeManager.isAnalyzing)
    }

    // MARK: - Progress Card

    private var progressCard: some View {
        VStack(spacing: 12) {
            ProgressView(value: organizeManager.analysisProgress)
                .tint(.blue)

            if !organizeManager.currentStep.isEmpty {
                Text(organizeManager.currentStep)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Scan Action Card

    private var scanActionCard: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                organizeManager.startFullAnalysis()
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Start Scan"))
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text(String(localized: "Find duplicates, similar photos, screenshots and more"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

// MARK: - Category Thumbnails

struct CategoryThumbnails: View {
    let identifiers: [String]
    @State private var assets: [PHAsset] = []

    private let thumbSize: CGFloat = 52
    private let overlap: CGFloat = 20

    var body: some View {
        Group {
            if assets.isEmpty {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            } else {
                ZStack {
                    ForEach(Array(assets.prefix(3).enumerated()), id: \.offset) { index, asset in
                        thumbView(for: asset)
                            .offset(x: overlap * CGFloat(index))
                            .zIndex(Double(2 - index))
                    }
                }
                .frame(
                    width: thumbSize + overlap * CGFloat(max(min(assets.count, 3) - 1, 0)),
                    height: thumbSize
                )
            }
        }
        .onAppear { loadAssets() }
        .onChange(of: identifiers) { _, _ in loadAssets() }
    }

    private func thumbView(for asset: PHAsset) -> some View {
        AssetImage(asset: asset, targetSize: CGSize(width: 200, height: 200), contentMode: .fill)
            .aspectRatio(1, contentMode: .fill)
            .frame(width: thumbSize, height: thumbSize)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }

    private func loadAssets() {
        guard !identifiers.isEmpty else { return }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var loaded: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            loaded.append(asset)
        }
        assets = identifiers.compactMap { id in
            loaded.first { $0.localIdentifier == id }
        }
    }
}
