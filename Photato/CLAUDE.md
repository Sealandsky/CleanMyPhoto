# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Photato** is a SwiftUI iOS app for cleaning and organizing photo libraries. Users can browse photos in a grid, swipe-gesture fullscreen browse, detect duplicates/similar/large/low-quality photos, and manage a soft-delete trash system. Monetized via StoreKit 2 subscriptions (monthly/yearly/lifetime).

## Build and Run

```bash
# Open in Xcode
open ../Photato.xcodeproj

# Build from CLI
xcodebuild -project ../Photato.xcodeproj -scheme CleanMyPhoto -configuration Debug build

# Run on simulator
xcodebuild -project ../Photato.xcodeproj -scheme CleanMyPhoto -destination 'platform=iOS Simulator,name=iPhone 16' build
```

The Xcode project is named `Photato.xcodeproj` but the Xcode scheme is still `CleanMyPhoto`.

## Architecture

MVVM with SwiftUI. `@MainActor` ViewModels use `@Published` to drive all UI. No external dependencies.

### App Flow

1. **Welcome** (`WelcomePage.swift`) — shown once, gated by `@AppStorage("hasShownWelcome")`
2. **Membership intro** (`MembershipView.swift`) — shown once after welcome, gated by `@AppStorage("hasShownMembership")`
3. **MainTabView** — 3 tabs: Library (ContentView), Organize, Settings
4. **ContentView** — photo grid with 3 sub-tabs (Library / Albums / Timeline), fullscreen viewer via `DraggablePhotoView`
5. **Organize** — scan for duplicates/similar/screenshots/large/low-quality, results in `OrganizeResultsView`

### Key ViewModels

| ViewModel | Role |
|-----------|------|
| `PhotoManager` | Central photo state: fetch, paginate (50/batch), cache via `PHCachingImageManager`, trash soft-delete, permissions |
| `MembershipManager` | StoreKit 2 purchases, trial status, premium gating |
| `PhotoOrganizeManager` | Photo analysis (similarity, duplicates, screenshots, large files, low quality), paginated results, JSON cache |
| `StatisticsManager` | Tracks deletion counts, space saved |
| `AlbumManager` / `SystemAlbumManager` | User albums and system date-based albums |
| `SelectionManager` | Generic multi-select state shared across list views |

### Navigation

- **Library tab**: 3 internal sub-tabs (Library/Albums/Timeline) managed by `MainTab` enum in ContentView, each with its own `NavigationStack` + `NavigationPath`
- **Organize tab**: `NavigationStack` with `OrganizeDestination.categoryResults(...)` pushed to `OrganizeResultsView`
- **Albums/Timeline**: `NavigationDestination` enums (`AlbumsDestination`, `TimelineDestination`) for drill-down navigation
- **Fullscreen**: overlay via `isFullscreenMode` state toggle (not a navigation push), uses `DraggablePhotoView`

### Photo Deletion Flow

1. Swipe up or select → `addToTrash()` → photo added to `pendingDeletionIDs` set, filtered from display
2. Trash view shows soft-deleted items, user can restore or permanently delete
3. `emptyTrash()` calls `PHPhotoLibrary.performChanges` for actual iOS deletion

### Organize System

- `OrganizeCategory` enum: `.similar`, `.duplicates`, `.screenshots`, `.lowQuality`, `.largeFiles`
- Scan results cached to `OrganizeCache.json` for instant reload
- Grouped layout (similar/duplicates) vs flat grid (screenshots/large/lowQuality)
- `OrganizeResultsView` has its own fullscreen viewer with trash access

### Membership / Paywall

- `SubscriptionType` enum with product IDs: `com.cleanmyphoto.subscription.monthly`, `.yearly`, `com.cleanmyphoto.purchase.lifetime`
- Display prices: $2.99/mo, $12.99/yr (64% savings), $23.99 lifetime
- `MembershipView` shown as fullScreenCover, has `isMandatory` flag (no dismiss when mandatory)
- Premium check: `membershipManager.isPremiumMember`

## Project Context

This is a SwiftUI photo app. All UI work should use SwiftUI conventions. Prefer SwiftUI-native approaches (GeometryReader, @available checks) over UIKit workarounds.

## File Organization

```
CleanMyPhoto/
├── Models/              # PhotoAsset, OrganizeResult, SubscriptionProduct, MembershipStatus
├── ViewModels/          # PhotoManager, MembershipManager, PhotoOrganizeManager, etc.
├── Views/
│   ├── Components/      # Reusable: PhotoCell, ProductCard, DateSection, MonthSection
│   ├── Organize/        # OrganizeView, OrganizeResultsView
│   ├── Navigation/      # NavigationDestinations.swift (route enums)
│   └── [Screens]        # ContentView, MainTabView, MembershipView, SettingsView, etc.
├── Extensions/          # PHAsset+Image
├── Resources/           # CleanMyPhotoApp.swift (app entry), Localizable.xcstrings
└── Utils/               # GridColumnHelper, ScreenSizeHelper, PHAssetSizeHelper, etc.
```

## Bug Fixing Rules

- When fixing UI bugs, always check ALL views that use a shared component or pattern — not just the one the user mentions. If a caching fix is needed in one view, search for the same pattern in sibling views.
- Before investigating formatting or display bugs, first verify the bug actually exists by reading the current code and checking if the issue might be locale-related or already resolved.

## UI Change Rules

- When the user describes where a UI element should be placed, confirm the specific screen/view name before making changes. Distinguish between 'list page' vs 'detail/fullscreen page' vs 'grid view' explicitly.
- Do not apply frosted glass / .ultraThinMaterial / blur effects to icons or small UI elements unless explicitly requested. Keep icon styles simple by default (plain SF Symbol, solid color).
