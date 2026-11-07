import SwiftUI
import Combine

// MARK: - On This Day Section View
/// 「过去的今天」横滑卡片区组件：
/// 置顶于「回忆」页（DiscoverView）上方，自动呈现往昔今天的各年份卡片。
struct OnThisDaySectionView: View {
    @ObservedObject var manager: OnThisDayManager
    var onSelectYear: (OnThisDayYearGroup) -> Void

    var body: some View {
        if !manager.yearGroups.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                headerView
                carouselView
            }
            .padding(.top, 4)
            .padding(.bottom, 6)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(manager.isMonthFallback ? String(localized: "Past Month Highlights") : String(localized: "On This Day"))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(.primary)

            Text(currentDateText)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(Color(.secondaryLabel))

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Carousel
    private var carouselView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(manager.yearGroups) { group in
                    OnThisDayCardView(group: group) {
                        onSelectYear(group)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .scrollClipDisabled()
    }

    // MARK: - Date Helper
    private var currentDateText: String {
        let now = Date()
        if manager.isMonthFallback {
            return now.formatted(.dateTime.month())
        } else {
            return now.formatted(.dateTime.month().day())
        }
    }
}
