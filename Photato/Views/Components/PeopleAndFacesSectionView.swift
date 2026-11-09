import SwiftUI

// MARK: - People And Faces Section View
/// 相册主页「人物与面孔」横滑合辑分区：
/// 位于「我的相簿」与「岁月足迹」之间，呈现多图错落拼贴卡片。
struct PeopleAndFacesSectionView: View {
    @ObservedObject var manager: PeopleRecognitionManager
    var onPersonSelect: ((PersonEntity) -> Void)? = nil
    var onViewAllPeople: (() -> Void)? = nil

    var body: some View {
        // 若已完成扫描且未检测到任何人物，优雅隐藏折叠，不产生视觉噪音
        if manager.hasScannedOnce && manager.people.isEmpty && !manager.isScanning {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // 1. 分区标题栏
                sectionHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 10)

                // 2. 横滑卡片流
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: PeopleCardMetrics.spacing) {
                        if manager.isScanning && manager.people.isEmpty {
                            // 扫描初始阶段骨架屏
                            skeletonCard
                            skeletonCard
                        } else {
                            ForEach(Array(manager.people.enumerated()), id: \.element.id) { index, person in
                                PersonHeroCardView(
                                    person: person,
                                    index: index + 1,
                                    onSelect: {
                                        onPersonSelect?(person)
                                    },
                                    onToggleFavorite: {
                                        manager.toggleFavorite(person)
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4) // 容纳卡片微外阴影
                }
            }
        }
    }

    // MARK: - Section Header
    private var sectionHeader: some View {
        HStack(alignment: .center) {
            Text(String(localized: "People & Faces"))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(.primary)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            if manager.isScanning && manager.people.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text(String(localized: "Identifying People…"))
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.secondary)
                }
            } else if !manager.people.isEmpty {
                Button {
                    onViewAllPeople?()
                } label: {
                    Text(String(format: String(localized: "%lld People ›"), Int64(manager.people.count)))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Skeleton Shimmer Card
    private var skeletonCard: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(height: PeopleCardMetrics.photoAreaHeight)

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 60, height: 12)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                        .frame(width: 40, height: 9)
                }

                Spacer()
            }
            .frame(height: 44)
        }
        .padding(PeopleCardMetrics.innerPadding)
        .frame(width: PeopleCardMetrics.cardWidth, height: PeopleCardMetrics.cardHeight)
        .background(Color.peopleCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: PeopleCardMetrics.cornerRadius, style: .continuous))
        .shimmering()
    }
}
