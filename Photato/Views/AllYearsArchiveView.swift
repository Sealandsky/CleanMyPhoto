import SwiftUI
import Photos

// MARK: - All Years Archive View
/// 「时光归档」全部年份纵向日历展开视图：
/// 纵向排列每一个历史年份，下方以 4 列 3:4 比例月份封面卡片平铺整年日历。
struct AllYearsArchiveView: View {
    @ObservedObject var manager: TimelineArchiveManager
    let onMonthSelect: (TimelineMonthItem) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(manager.availableYears, id: \.self) { year in
                    yearSection(year: year)
                }
            }
            .padding(.vertical, 12)
        }
        .background(Color.pageBackground)
        .navigationTitle(String(localized: "Timeline Archive"))
        .navigationBarTitleDisplayMode(.inline)
        .dynamicSecondaryNavigationBar()
        .toolbar(.hidden, for: .tabBar)
        .task {
            await manager.loadAllYears()
        }
    }

    @ViewBuilder
    private func yearSection(year: Int) -> some View {
        let months = manager.monthsByYear[year] ?? []
        VStack(alignment: .leading, spacing: 8) {
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
            .padding(.top, 4)

            // 4 列自适应网格（对齐 Colo v2.0 规范）
            if months.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .task {
                        await manager.selectYear(year)
                    }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(months) { item in
                        monthCard(item: item)
                            .onTapGesture {
                                SoundManager.playAction()
                                onMonthSelect(item)
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
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
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                MonthCardImage(asset: item.coverAsset)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                // 底部 55% 黑色渐变遮罩
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.4), location: 0.35),
                        .init(color: .black.opacity(0.85), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: geo.size.height * 0.55)
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.monthName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)

                    Text(String(localized: "\(item.photoCount) Photos"))
                        .font(.system(size: 9.5, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                }
                .padding(6)
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        )
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
                targetSize: CGSize(width: 300, height: 400),
                contentMode: .aspectFill,
                options: options
            ) { img, _ in
                self.image = img
            }
        }
    }
}
