import SwiftUI
import Photos

// MARK: - All Years Archive View
/// 「时光归档」全部年份纵向展开视图：
/// 纵向排列每一个历史年份，横滑浏览该年份下的全部月份卡片。
struct AllYearsArchiveView: View {
    @ObservedObject var manager: TimelineArchiveManager
    let onMonthSelect: (TimelineMonthItem) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(manager.availableYears, id: \.self) { year in
                    yearSection(year: year)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color.pageBackground)
        .navigationTitle(String(localized: "Timeline Archive"))
        .navigationBarTitleDisplayMode(.inline)
        .dynamicSecondaryNavigationBar()
        .toolbar(.hidden, for: .tabBar)
    }

    @ViewBuilder
    private func yearSection(year: Int) -> some View {
        let months = manager.monthsByYear[year] ?? []
        VStack(alignment: .leading, spacing: 10) {
            // 年份标题行
            HStack {
                Text(yearTitle(for: year))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer()

                let total = months.reduce(0) { $0 + $1.photoCount }
                if total > 0 {
                    Text(String(localized: "\(total) Photos"))
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)

            // 月份卡片横滑
            if months.isEmpty {
                // 若该年份未预加载，发起异步拉取
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 112)
                    .task {
                        await manager.selectYear(year)
                    }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(months) { item in
                            monthCard(item: item)
                                .onTapGesture {
                                    SoundManager.playAction()
                                    onMonthSelect(item)
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func yearTitle(for year: Int) -> String {
        let currentLang = Locale.current.language.languageCode?.identifier ?? ""
        if currentLang.hasPrefix("zh") {
            return "\(year)年"
        }
        return "\(year)"
    }

    private func monthCard(item: TimelineMonthItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            MonthCardImage(asset: item.coverAsset)
                .frame(width: 112, height: 112)
                .clipped()

            LinearGradient(
                colors: [.black.opacity(0.72), .black.opacity(0.35), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 48)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.monthName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)

                Text(String(localized: "\(item.photoCount) Photos"))
                    .font(.system(size: 11.5, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 7)
        }
        .frame(width: 112, height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MonthCardImage: View {
    let asset: PHAsset?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
            }
        }
        .onAppear {
            guard let asset, image == nil else { return }
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 300, height: 300),
                contentMode: .aspectFill,
                options: options
            ) { img, _ in
                self.image = img
            }
        }
    }
}
