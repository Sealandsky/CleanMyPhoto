import SwiftUI

struct OrganizeView: View {
    @Bindable var organizeManager: PhotoOrganizeManager
    @ObservedObject var photoManager: PhotoManager
    let onCategorySelect: (OrganizeCategory) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                categoryCards

                if organizeManager.isAnalyzing {
                    progressCard
                } else if organizeManager.totalGroupCount == 0 && organizeManager.hasLoadedInitialData {
                    scanActionCard
                }
            }
            .padding(.bottom, 16)
        }
        .background(Color.black)
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

    // MARK: - Progress Card

    private var progressCard: some View {
        VStack(spacing: 12) {
            ProgressView(value: organizeManager.analysisProgress)
                .tint(.white)

            if !organizeManager.currentStep.isEmpty {
                Text(organizeManager.currentStep)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Category Cards

    private var categoryCards: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            ForEach(OrganizeCategory.allCases) { category in
                categoryCard(for: category)
            }
        }
        .padding(.horizontal, 16)
    }

    private func categoryCard(for category: OrganizeCategory) -> some View {
        let count = organizeManager.stat(for: category)
        let hasResults = count > 0

        return Button {
            if hasResults {
                onCategorySelect(category)
            } else {
                organizeManager.startFullAnalysis()
            }
        } label: {
            VStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.system(size: 32))
                    .foregroundColor(hasResults ? .white : .white.opacity(0.4))

                Text(category.localizedText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)

                if hasResults {
                    Text("\(count)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                } else {
                    Text(String(localized: "Scan"))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .opacity(hasResults ? 1 : 0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(hasResults ? 0.2 : 0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(organizeManager.isAnalyzing)
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
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Start Scan"))
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    Text(String(localized: "Find duplicates, similar photos, screenshots and more"))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
