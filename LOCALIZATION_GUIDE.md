# Photato（图豆）本地化指南

> 2026-11-06 重写（@naming）。旧版指南描述的是 CleanMyPhoto 时期的 2 语言初版方案，已整体过时，本文以当前代码为准。

## 现状

- **机制**：String Catalog（`Photato/Resources/Localizable.xcstrings`）+ 代码里 `String(localized:)` / SwiftUI 的 `LocalizedStringKey`。
- **规模**：372 个 key，36 个 Swift 文件在使用，无硬编码用户可见文本残留。
- **语言**（7 种）：简体中文 zh-Hans（主语言）、繁体中文 zh-Hant、英语 en（源语言）、西班牙语 es、日语 ja、韩语 ko、葡萄牙语 pt-BR。
- **InfoPlist**：`InfoPlist.xcstrings` 覆盖 CFBundleDisplayName / CFBundleName / 相册权限两条用途描述，7 语言齐全。改权限文案时两处（xcstrings + 代码 fallback）都要动。

## 规则

1. **key = 英文源文**。新字符串直接写英文原文作 key，Xcode 自动补进 xcstrings；不要造抽象 key（如 `home.title.main`）。
2. **新增字符串必须 7 语言全填**。xcstrings 里 Xcode 会标红缺失语言；提交前把 ⚠️ 清零。机翻初稿可以，但 zh-Hans 必须人工过一遍。
3. **中文术语以 copy.md v1 为准**（2026-11-06 频道交付）。核心几条：
   - 待删区一律「待处理照片」（en: Pending Photos），不再出现「回收站 / Trash / 已删除照片」；
   - 会员名一律「图豆 Pro」（en: Photato Pro），不再用「专业版」；
   - 系统照片库＝图库，用户自建＝相簿，权限语境可用「相册权限」；
   - 称谓用「你」不用「您」；省略号用「…」不用「...」。
4. **数字与单位**：照片类量词用「张」，视频用「个视频」；带占位符的用 `%lld` / `%@`，多占位符按 `%1$lld` 显式标序（中日语序不同，必须标）。
5. **复数**：countable 字符串在 xcstrings 里用 variations/plural，不要用 `%lld photos(s)` 这种拼接。

## 常用操作

```swift
// 代码里取字符串（含参数）
String(localized: "Found \(count) similar photos")
// SwiftUI 里直接写字符串字面量即可（自动本地化）
Text("Scan Completed")
```

- 新增语言：xcstrings 里目标语言列填翻译即可，工程无需加 lproj。
- 校验：构建后看 Xcode String Catalog 界面，凡有 ⚠️（缺失/未翻译）先清再提交。
- 网站与隐私政策：站内页面在 `web/`（AirHost 部署，photato.apps.air.build），语言覆盖与 App 相同的 7 种，由 @website 维护。
