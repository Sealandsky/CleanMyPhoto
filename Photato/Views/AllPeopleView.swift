import SwiftUI

// MARK: - All People View
/// 「全部人物」总览网格页：
/// 呈现所有已识别聚类的人物卡片，支持点击进入二级详情流、收藏置顶与快速筛选。
struct AllPeopleView: View {
    @ObservedObject var peopleManager: PeopleRecognitionManager
    @ObservedObject var photoManager: PhotoManager
    var onPersonSelect: ((PersonEntity) -> Void)? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if peopleManager.people.isEmpty {
                    emptyStateView
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(peopleManager.people.enumerated()), id: \.element.id) { index, person in
                            PersonHeroCardView(
                                person: person,
                                index: index + 1,
                                onSelect: {
                                    onPersonSelect?(person)
                                },
                                onToggleFavorite: {
                                    peopleManager.toggleFavorite(person)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    // 底部端侧隐私保障说明
                    privacyFooter
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
            }
        }
        .background(Color.pageBackground)
        .navigationTitle(String(localized: "People"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PendingPhotosEntryButton()
            }
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 52))
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.top, 80)

            Text(String(localized: "No People Found"))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)

            Text(String(localized: "Photos with clear faces will appear here automatically."))
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Privacy Footer
    private var privacyFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 12))
            Text(String(localized: "People recognition runs entirely on your device. No photos or face data ever leave your phone."))
                .font(.system(size: 12, design: .rounded))
        }
        .foregroundColor(.secondary.opacity(0.7))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
    }
}
