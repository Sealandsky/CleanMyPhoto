import SwiftUI
import Photos

// MARK: - Album Scan Progress Sheet
/// 相簿相似照片智能扫描半屏面板：
/// 1. 扫描进行中：展示呼吸动画图标、渐变进度条、百分比与已扫描张数统计，支持轻量取消；
/// 2. 扫描完成：展示成功徽章、结果文案、发现照片的横向缩略图卡片预览；
/// 3. 底部确定按钮：点击后将结果传递给上层相簿二级页，平滑替换上屏。
struct AlbumScanProgressSheet: View {
    let album: AlbumModel
    let albumAssets: [PHAsset]
    let excludingIDs: Set<String>
    let onConfirm: ([PhotoAsset]) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var isScanning: Bool = true
    @State private var progress: Double = 0.0
    @State private var processedCount: Int = 0
    @State private var totalCount: Int = 0
    @State private var foundPhotos: [PhotoAsset] = []
    @State private var isCompleted: Bool = false
    @State private var scanError: String? = nil

    // 动画状态
    @State private var iconPulsing: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // 顶部抓手条下方间距
            Spacer()
                .frame(height: 20)

            ZStack {
                if isCompleted {
                    completedContent
                        .transition(.opacity.animation(.easeInOut(duration: 0.38)))
                } else {
                    scanningContent
                        .transition(.opacity.animation(.easeInOut(duration: 0.28)))
                }
            }

            Spacer(minLength: 12)

            // 底部操作区
            bottomActionArea
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .presentationDetents([.fraction(0.48), .medium])
        .presentationDragIndicator(.visible)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .task {
            await startScan()
        }
    }

    // MARK: - Scanning Content
    private var scanningContent: some View {
        VStack(spacing: 20) {
            // 扫描动效图标
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.18), Color.teal.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .scaleEffect(iconPulsing ? 1.08 : 0.96)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: iconPulsing)

                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .onAppear {
                iconPulsing = true
            }

            // 文本说明
            VStack(spacing: 6) {
                Text(String(localized: "Building Library AI Index..."))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(String(localized: "Analyzing visual features to unlock smart recommendations for all albums"))
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            // 进度条与张数
            VStack(spacing: 8) {
                ProgressView(value: max(0.02, progress))
                    .tint(.accentColor)
                    .progressViewStyle(.linear)

                HStack {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)

                    Spacer()

                    if totalCount > 0 {
                        Text(String(localized: "Indexed \(processedCount) of \(totalCount)"))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    } else {
                        Text(String(localized: "Preparing library..."))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
        }
        .padding(.top, 8)
    }

    // MARK: - Completed Content
    private var completedContent: some View {
        VStack(spacing: 16) {
            // 完成状态图标徽章
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: foundPhotos.isEmpty
                                ? [Color.gray.opacity(0.2), Color.gray.opacity(0.1)]
                                : [Color.green.opacity(0.18), Color.teal.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                Image(systemName: foundPhotos.isEmpty ? "checkmark.circle" : "checkmark.seal.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(
                        foundPhotos.isEmpty
                            ? LinearGradient(colors: [Color.secondary], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [Color.green, Color.teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            .padding(.top, 4)

            // 结果文案
            VStack(spacing: 6) {
                Text(String(localized: "AI Index Ready"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                if !foundPhotos.isEmpty {
                    Text(String(localized: "All albums unlocked! Found \(foundPhotos.count) photos for this album."))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                } else {
                    Text(String(localized: "All albums unlocked! Current album is already complete."))
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }

            // 缩略图预览气泡（有结果时横向滑动展示前 10 张）
            if !foundPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(foundPhotos.prefix(10)) { photo in
                            AssetImage(
                                asset: photo.asset,
                                targetSize: CGSize(width: 140, height: 140),
                                contentMode: .fill,
                                placeholderColor: Color(UIColor.tertiarySystemFill)
                            )
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .frame(height: 62)
                .padding(.top, 2)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Bottom Actions
    private var bottomActionArea: some View {
        Group {
            if isCompleted {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onConfirm(foundPhotos)
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                        Text(foundPhotos.isEmpty
                             ? String(localized: "Confirm")
                             : String(localized: "View Recommended Photos"))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    cancelScan()
                } label: {
                    Text(String(localized: "Cancel"))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Scan Actions
    private func startScan() async {
        isScanning = true
        progress = 0.05
        isCompleted = false

        do {
            let matcher = PhotoSimilarityMatcher.shared
            let matched: [PHAsset]
            if !matcher.isLibraryIndexed {
                matched = try await matcher.indexLibraryAndFindSimilar(
                    toAlbumAssets: albumAssets,
                    excludingIDs: excludingIDs,
                    topN: 30,
                    onProgress: { processed, total in
                        Task { @MainActor in
                            self.processedCount = processed
                            self.totalCount = total
                            if total > 0 {
                                self.progress = max(0.05, min(1.0, Double(processed) / Double(total)))
                            }
                        }
                    }
                )
            } else {
                matched = try await matcher.findSimilar(
                    toAlbumAssets: albumAssets,
                    excludingIDs: excludingIDs,
                    topN: 30,
                    onProgress: { processed, total in
                        Task { @MainActor in
                            self.processedCount = processed
                            self.totalCount = total
                            if total > 0 {
                                self.progress = max(0.05, min(1.0, Double(processed) / Double(total)))
                            }
                        }
                    }
                )
            }

            // 扫描平滑收尾
            withAnimation(.easeInOut(duration: 0.25)) {
                self.progress = 1.0
            }

            try? await Task.sleep(nanoseconds: 200_000_000)

            let photoAssets = matched.map { PhotoAsset(asset: $0) }
            withAnimation(.easeInOut(duration: 0.38)) {
                self.foundPhotos = photoAssets
                self.isScanning = false
                self.isCompleted = true
            }
        } catch {
            print("Album scan failed: \(error)")
            // 异常兜底：若取消或出错，直接收尾
            withAnimation(.easeInOut(duration: 0.2)) {
                self.isScanning = false
                self.isCompleted = true
                self.foundPhotos = []
            }
        }
    }

    private func cancelScan() {
        PhotoSimilarityMatcher.shared.cancelAlbumSearch()
        onCancel()
        dismiss()
    }
}
