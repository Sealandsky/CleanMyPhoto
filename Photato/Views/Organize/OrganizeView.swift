import SwiftUI
import Photos

struct OrganizeView: View {
    @Bindable var organizeManager: PhotoOrganizeManager
    @ObservedObject var photoManager: PhotoManager
    let onCategorySelect: (OrganizeCategory) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                scanCard
                categoryCards
            }
            .animation(.easeInOut(duration: 0.3), value: organizeManager.isAnalyzing)
            .animation(.easeInOut(duration: 0.3), value: organizeManager.totalGroupCount > 0)
            .padding(16)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .task {
            if organizeManager.totalGroupCount == 0 && !organizeManager.isAnalyzing {
                await performInitialScan()
            }
        }
    }

    private func performInitialScan() async {
        await organizeManager.quickAnalysis()
    }

    // MARK: - Scan Card

    @ViewBuilder
    private var scanCard: some View {
        if organizeManager.isAnalyzing {
            scanningCard
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else if organizeManager.totalGroupCount > 0 {
            rescanCard
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else if organizeManager.hasLoadedInitialData {
            startScanCard
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var startScanCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Start Scan"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                Text(String(localized: "Find duplicates, similar photos, screenshots and more"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    organizeManager.startFullAnalysis()
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(String(localized: "Scan"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                )
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }

    private var rescanCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                let totalCount = OrganizeCategory.allCases.reduce(0) { $0 + organizeManager.stat(for: $1) }
                Text(String(localized: "Found \(totalCount) items"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                Text(String(localized: "Tap a category below to review"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    organizeManager.startFullAnalysis()
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(String(localized: "Rescan"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                )
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }

    private var scanningCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(organizeManager.currentStep.isEmpty
                     ? String(localized: "Scanning...")
                     : organizeManager.currentStep)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                ProgressView(value: organizeManager.analysisProgress)
                    .tint(.blue)
            }

            Spacer()

            Button {
                organizeManager.cancelAnalysis()
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(String(localized: "Cancel"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                )
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
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
            .prefix(2))

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
                    .padding(.trailing, -4)
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
        .opacity(organizeManager.isAnalyzing ? 0.5 : 1)
    }
}

// MARK: - Category Thumbnails

struct CategoryThumbnails: View {
    let identifiers: [String]
    @State private var assets: [PHAsset] = []

    private let thumbWidth: CGFloat = 52
    private let thumbRatio: CGFloat = 4.0 / 3.0 // 3:4 portrait (height / width)

    var body: some View {
        Group {
            if assets.isEmpty {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            } else {
                ZStack {
                    ForEach(Array(assets.prefix(2).enumerated()), id: \.offset) { index, asset in
                        thumbView(for: asset)
                            .rotationEffect(.degrees(index == 0 ? -8 : 6))
                            .offset(x: index == 0 ? -8 : 10, y: index == 0 ? 2 : -2)
                            .zIndex(index == 0 ? 0 : 1)
                    }
                }
                .frame(
                    width: thumbWidth * 2 + 10,
                    height: thumbWidth * thumbRatio + 8
                )
            }
        }
        .onAppear { loadAssets() }
        .onChange(of: identifiers) { _, _ in loadAssets() }
    }

    private func thumbView(for asset: PHAsset) -> some View {
        let height = thumbWidth * thumbRatio
        return AssetImage(asset: asset, targetSize: CGSize(width: 200, height: 280), contentMode: .fill)
            .aspectRatio(3.0 / 4.0, contentMode: .fill)
            .frame(width: thumbWidth, height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
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
