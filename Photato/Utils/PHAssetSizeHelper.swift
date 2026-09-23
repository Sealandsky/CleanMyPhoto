import Photos
import ObjectiveC

/// 全部 nonisolated：方法为纯计算（无共享可变状态），
/// 供 Task.detached / 后台任务组直接调用，不产生主线程回跳
enum PHAssetSizeHelper {
    /// NSCache 自身线程安全；nonisolated(unsafe) 允许从 nonisolated 方法直接访问
    private nonisolated(unsafe) static let cache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 10000
        return cache
    }()

    nonisolated static func getCachedSize(for asset: PHAsset) -> Int64? {
        cache.object(forKey: asset.localIdentifier as NSString)?.int64Value
    }

    nonisolated static func getAssetSize(_ asset: PHAsset) async -> Int64 {
        if let cached = getCachedSize(for: asset) {
            return cached
        }

        // 1. 优先使用 PHAssetResource 获取元数据文件大小（支持视频、图片、实况、iCloud，毫秒级响应）
        let fastSize = getFileSize(asset)
        if fastSize > 0 {
            cache.setObject(NSNumber(value: fastSize), forKey: asset.localIdentifier as NSString)
            return fastSize
        }

        // 2. 若为图片，回退到请求图片数据长度
        if asset.mediaType == .image {
            let size = await withCheckedContinuation { continuation in
                let options = PHImageRequestOptions()
                options.isNetworkAccessAllowed = false
                options.deliveryMode = .fastFormat

                PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                    continuation.resume(returning: Int64(data?.count ?? 0))
                }
            }
            if size > 0 {
                cache.setObject(NSNumber(value: size), forKey: asset.localIdentifier as NSString)
                return size
            }
        }

        // 3. 降级方案：使用 PHAssetResourceManager 数据流测量（适用于视频或 KVC 属性不可用场景）
        let streamSize = await requestResourceDataStreamSize(for: asset)
        if streamSize > 0 {
            cache.setObject(NSNumber(value: streamSize), forKey: asset.localIdentifier as NSString)
            return streamSize
        }

        return 0
    }

    nonisolated static func getFileSize(_ asset: PHAsset) -> Int64 {
        if let cached = getCachedSize(for: asset) {
            return cached
        }
        let resources = PHAssetResource.assetResources(for: asset)
        let size = resources.reduce(Int64(0)) { sum, resource in
            sum + safeFileSize(for: resource)
        }
        if size > 0 {
            cache.setObject(NSNumber(value: size), forKey: asset.localIdentifier as NSString)
        }
        return size
    }

    /// 安全提取 PHAssetResource 的 fileSize 属性。
    /// 增加动态 selector 防护，避免在属性移除或重命名的系统版本触发 NSUndefinedKeyException。
    private nonisolated static func safeFileSize(for resource: PHAssetResource) -> Int64 {
        let resourceObj = resource as AnyObject
        let key = "fileSize"
        let selector = NSSelectorFromString(key)

        // 防御性校验：确认当前对象响应 fileSize 消息
        guard resourceObj.responds(to: selector) else {
            return 0
        }

        // 安全提取值，兼容 NSNumber 与直接 Int64 桥接类型，绝不引发未捕获异常
        if let num = resource.value(forKey: key) as? NSNumber {
            return num.int64Value
        } else if let size = resource.value(forKey: key) as? Int64 {
            return size
        }
        return 0
    }

    /// 降级测量：通过 PhotoKit 原生 PHAssetResourceManager 流式分块累加资源数据体积，保证零崩溃与真实测量
    private nonisolated static func requestResourceDataStreamSize(for asset: PHAsset) async -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        guard !resources.isEmpty else { return 0 }

        var totalSize: Int64 = 0
        for resource in resources {
            if Task.isCancelled { break }
            let resourceSize = await withCheckedContinuation { (continuation: CheckedContinuation<Int64, Never>) in
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = false
                var accumulated: Int64 = 0
                let lock = NSLock()
                var hasResumed = false

                PHAssetResourceManager.default().requestData(
                    for: resource,
                    options: options,
                    dataReceivedHandler: { data in
                        lock.lock()
                        accumulated += Int64(data.count)
                        lock.unlock()
                    },
                    completionHandler: { error in
                        lock.lock()
                        defer { lock.unlock() }
                        guard !hasResumed else { return }
                        hasResumed = true
                        continuation.resume(returning: error == nil ? accumulated : 0)
                    }
                )
            }
            totalSize += resourceSize
        }
        return totalSize
    }

    /// 批量计算一组素材的总体积：优先读取内存缓存，未命中部分受控并发拉取并自动回填缓存
    nonisolated static func calculateTotalSize(for assets: [PHAsset], maxConcurrency: Int = 16) async -> Int64 {
        guard !assets.isEmpty else { return 0 }

        var uncached: [PHAsset] = []
        var cachedTotal: Int64 = 0

        for asset in assets {
            if let cached = getCachedSize(for: asset) {
                cachedTotal += cached
            } else {
                uncached.append(asset)
            }
        }

        guard !uncached.isEmpty else { return cachedTotal }

        let uncachedTotal = await withTaskGroup(of: Int64.self, returning: Int64.self) { group in
            var running = 0
            var groupTotal: Int64 = 0

            for asset in uncached {
                if Task.isCancelled { break }
                if running >= maxConcurrency {
                    if let size = await group.next() {
                        groupTotal += size
                        running -= 1
                    }
                }
                group.addTask {
                    await getAssetSize(asset)
                }
                running += 1
            }

            for await size in group {
                groupTotal += size
            }
            return groupTotal
        }

        return cachedTotal + uncachedTotal
    }
}
