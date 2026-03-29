# CleanMyPhoto 本地化配置指南

## ✅ 已完成的工作

### 1. 创建了 String Catalog 文件
- **文件路径**: `CleanMyPhoto/Resources/Localizable.xcstrings`
- **支持语言**: 简体中文 (zh-Hans)、英文 (en)
- **包含字符串**: 80+ 个本地化字符串

### 2. 已本地化的文件
✅ `ContentView.swift` - 主视图
✅ `AlbumPhotoListView.swift` - 相簿照片列表
✅ `AlbumCell.swift` - 相簿单元格
✅ `AlbumModel.swift` - 相簿模型
✅ `TrashView.swift` - 回收站视图
✅ `WelcomePage.swift` - 欢迎页面

## 📋 需要本地化的剩余文件

### 重要程度：高
以下文件包含用户界面文本，建议优先本地化：

#### 1. `MembershipView.swift`
包含的主要文本：
- "升级到专业版"
- "解锁所有功能"
- "会员权益"
- "订阅说明"
- "继续"、"恢复购买"、"稍后升级"
- "购买成功"、"确定"、"感谢您的支持！"
- "提示"

**修改示例**:
```swift
// 修改前
Text("升级到专业版")

// 修改后
Text(String(localized: "升级到专业版"))
```

#### 2. `SubscriptionProduct.swift`
包含的主要文本：
- "月度订阅"、"年度订阅"、"终身会员"
- "省53%"
- "最受欢迎"
- "一次性购买"

**修改示例**:
```swift
// 修改前
case .monthly: return "月度订阅"

// 修改后
case .monthly: return String(localized: "月度订阅")
```

#### 3. `MembershipManager.swift`
包含的错误消息：
- "加载产品失败: %@"
- "产品未找到"
- "购买等待确认"
- "购买失败: %@"
- "恢复购买失败: %@"

**修改示例**:
```swift
// 修改前
self.purchaseError = "加载产品失败: \(error.localizedDescription)"

// 修改后
self.purchaseError = String(localized: "加载产品失败: \(error.localizedDescription)")
```

#### 4. `ProductCard.swift`
包含的主要文本：
- "一次性"（durationText 为空时）
- "最受欢迎"

## 🔧 如何完成剩余本地化

### 方法 1：手动替换（推荐用于少量修改）

```swift
// 修改前
Text("中文字符串")

// 修改后
Text(String(localized: "中文字符串"))
```

### 方法 2：使用 NSLocalizedString（推荐用于格式化字符串）

```swift
// 带参数的本地化字符串
String(localized: "试用期还剩 \(days) 天")

// 或者使用 String interpolation
let text = String(format: String(localized: "试用期还剩 %d 天"), days)
```

## ⚙️ 配置 Xcode 项目

### 添加本地化支持

1. **在 Xcode 中打开项目**
   - 选择 `CleanMyPhoto.xcodeproj`
   - 选中项目（蓝色图标）

2. **添加本地化**
   - 选择 `Info` 标签
   - 在 `Localizations` 区域点击 `+`
   - 添加 `Chinese (Simplified)` 和 `English`

3. **验证 String Catalog**
   - 确保在项目导航器中可以看到 `Localizable.xcstrings`
   - 文件应该在 `CleanMyPhoto/Resources/` 目录下

## 🧪 测试本地化

### 在模拟器中测试

1. **更改系统语言**
   - 打开 Settings -> General -> Language & Region
   - 选择 Add Language
   - 添加并切换到中文/英文

2. **重启应用**
   - 杀死应用并重新启动
   - 验证所有文本是否正确显示为所选语言

### 预览不同语言

```swift
#Preview("English") {
    ContentView()
        .environment(\.locale, .init(identifier: "en"))
}

#Preview("中文") {
    ContentView()
        .environment(\.locale, .init(identifier: "zh-Hans"))
}
```

## 📝 本地化最佳实践

### 1. 字符串提取原则
- ✅ 所有用户可见的文本都应该本地化
- ❌ 代码中的调试信息不需要本地化
- ❌ API 密钥、配置等不需要本地化

### 2. 参数化字符串
```swift
// ✅ 好的做法
String(localized: "删除 \(count) 张照片")

// ❌ 不好的做法
let text = count == 1 ? "删除 1 张照片" : "删除 \(count) 张照片"
```

### 3. 复数形式处理
```swift
// String Catalog 支持复数规则
Text("^[\(count) photo](inflect: true)")
```

### 4. 文本长度考虑
- 英文文本通常比中文长 20-30%
- UI 布局应该考虑文本长度变化
- 使用 `.fixedSize()` 或 `.lineLimit(null)` 避免截断

## 🎯 快速检查清单

- [ ] 所有 `Text("中文")` 已替换为 `Text(String(localized: "中文"))`
- [ ] 所有 Button 文本已本地化
- [ ] 所有 Alert 标题和消息已本地化
- [ ] 所有 NavigationBar 标题已本地化
- [ ] 错误消息已本地化
- [ ] 在两种语言下测试所有页面
- [ ] 检查文本布局是否在不同语言下正常

## 📚 参考资源

- [Apple Localizations Guide](https://developer.apple.com/documentation/xcode/localization)
- [String Catalog Documentation](https://developer.apple.com/documentation/xcode/string-catalogs)
- [Localization in SwiftUI](https://developer.apple.com/documentation/swiftui/localizing-string-resources-in-your-app)

## ✨ 完成效果

完成所有本地化后，您的应用将：
- ✅ 自动跟随系统语言切换
- ✅ 支持简体中文和英文
- ✅ 为将来添加更多语言做好准备
- ✅ 提升国际化用户体验
