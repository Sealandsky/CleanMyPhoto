修复重温页下拉刷新后大标题不回弹的问题。

## 根因
`.large` 大标题模式下，下拉刷新拖动大标题产生负向弹性偏移（rubber-band）；刷新完成时照片批次整批替换（ID 全新），与系统回弹动画竞争。现有的“带动画 scrollTo”在弹性状态下会被系统回弹吞掉，无法归位（用户截图已确认失效）。

## 改动（仅 `Photato/Views/DiscoverView.swift`）

1. **监听真实滚动偏移**：复用项目已有的 `ScrollOffsetPreferenceKey`（Utils/ScrollOffsetPreferenceKey.swift），把 gridView 的 ScrollView 偏移读入 `@State private var gridOffset: CGFloat`（负值 = 仍停在下拉位置）。

2. **新增归位轮询方法** `snapToTopAfterRefresh(proxy:)`：
   - 刷新闭包结束后执行：循环最多 10 次、每次间隔 100ms
   - 每次检查 `gridOffset`：若 ≥ 0（已回弹）提前退出；否则用 `withTransaction(Transaction(animation: nil))` + `proxy.scrollTo(topAnchorID, anchor: .top)` **无动画强制吸附**回顶部
   - 无动画事务不会被系统回弹动画取消；重试保证即使首次被吞也能拉回

3. **两处 `refreshable` 接入**：gridView 与 emptyStateView 的刷新闭包尾部都调用 `snapToTopAfterRefresh`；保留现有 0.6s 最小刷新时长。

4. **不动的东西**：Tab 重选滚顶信号（带动画 scrollTo）保持不变；`DiscoverManager` 采样逻辑不变；其他页面零触碰。

## 验证
- 编译 + 装入 iOS 18.5 模拟器
- 滚顶路径回归：TEMP 递增 `scrollToTopSignal` 截图确认网格回顶正常
- 下拉手势本环境无法模拟，交付后请用户真机/模拟器手动下拉刷新验证（松手后大标题与内容应立即回弹到顶部）

## 备注（如仍复发的后备方案）
若轮询归位仍被环境吞掉，后备方案是给 ScrollView 挂 `.id(manager.refreshGeneration)`（每次刷新完成递增，整体重建滚动视图、偏移强制归零）——有轻微重建闪烁风险，作为最后手段。