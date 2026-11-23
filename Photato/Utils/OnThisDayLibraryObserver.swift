import Foundation
import Photos

// MARK: - On This Day Library Observer
/// 监听图库的"真实删除"（emptyTrash → deleteAssets），触发往年今日快照强制重建。
///
/// 背景：OnThisDayManager 自身没有 PHPhotoLibraryChangeObserver，真删除后 yearGroups
/// 不会更新；若不重建快照，widget 会继续展示已被删除的封面/张数。
/// 本监听器只关心 removedObjects（真删除），忽略收藏/改名等内容变更，并做 1.5s 防抖。
///
/// 用法：在 MainTabView 里 `OnThisDayLibraryObserver.shared.start()`，
/// 并设置 `onLibraryChanged` 闭包去做 forceRefresh + 重建快照。
@MainActor
final class OnThisDayLibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
    static let shared = OnThisDayLibraryObserver()

    /// 检测到真删除后调用（由 MainTabView 注入：forceRefresh + rebuild）
    var onLibraryChanged: (@MainActor () async -> Void)?

    /// 基准 fetchResult，用于 changeDetails(for:) 比对出被移除的资产
    private var baselineFetchResult: PHFetchResult<PHAsset>?
    private var isObserving = false
    private var debounceTask: Task<Void, Never>?

    private override init() {
        super.init()
    }

    /// 注册监听并建立基准。可重复调用（幂等）。
    func start() {
        guard !isObserving else { return }
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false
        baselineFetchResult = PHAsset.fetchAssets(with: options)
        PHPhotoLibrary.shared().register(self)
        isObserving = true
    }

    deinit {
        // deinit 在隔离外，直接反注册即可（不触碰隔离属性）
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    // MARK: - PHPhotoLibraryChangeObserver

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        // 仿照 PhotoManager：只在主线程侧用 changeInstance 与基准比对
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let baseline = self.baselineFetchResult,
                  let details = changeInstance.changeDetails(for: baseline) else {
                // 基准缺失时刷新一次基准，避免永久失联
                let options = PHFetchOptions()
                options.includeHiddenAssets = false
                self.baselineFetchResult = PHAsset.fetchAssets(with: options)
                return
            }

            // 更新基准
            self.baselineFetchResult = details.fetchResultAfterChanges

            // 只关心真删除：removedObjects 非空
            guard !details.removedObjects.isEmpty else { return }

            // 防抖：批量删除合并成一次重建
            self.debounceTask?.cancel()
            let work = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                await self?.onLibraryChanged?()
            }
            self.debounceTask = work
        }
    }
}
