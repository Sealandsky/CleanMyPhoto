# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CleanMyPhoto is a SwiftUI iOS application for managing and organizing photo libraries. Users can browse photos in a grid view, view them fullscreen with gesture controls, and mark photos for deletion in a trash system.

## Build and Run

```bash
# Open the project in Xcode
open ../CleanMyPhoto.xcodeproj

# Build from command line
xcodebuild -project ../CleanMyPhoto.xcodeproj -scheme CleanMyPhoto -configuration Debug build

# Run on simulator (requires Xcode)
xcodebuild -project ../CleanMyPhoto.xcodeproj -scheme CleanMyPhoto -destination 'platform=iOS Simulator,name=iPhone 15' test
```

## Architecture

This project uses **MVVM (Model-View-ViewModel)** architecture with SwiftUI. The key architectural pattern is that `PhotoManager` (ViewModel) is `@MainActor` and uses `@Published` properties to drive UI updates in views.

### App Flow

1. **Welcome onboarding** (`WelcomePage.swift`) - Shown once, stored via `@AppStorage("hasShownWelcome")`
2. **Permission request** - Checks `PHPhotoLibrary.authorizationStatus` on launch via `PhotoManager.init()`
3. **Main list view** (`PhotoListView.swift`) - Grid layout, lazy-loaded with pagination (50 photos per batch)
4. **Fullscreen browse** (`DraggablePhotoView.swift`) - Gesture-based photo viewing
5. **Trash management** (`TrashView.swift`) - Soft-delete system before permanent deletion

### Key Components

**PhotoManager (ViewModel)**
- Centralized state management for photos, permissions, loading states
- Handles pagination with `maxPhotoCount = 50` and `hasMorePhotos` flag
- Manages photo cache using `PHCachingImageManager`
- `hasLoadedOnce` flag distinguishes "loading" from "empty library" states
- Permission status checked at initialization to avoid re-showing permission screens

**ContentView**
- Orchestrates list/fullscreen modes with `isFullscreenMode` state
- Manages navigation state: `currentPhotoID`, `scrollToPhotoID`, `navigationDirection`
- Uses custom asymmetric transition for photo-to-photo animations
- Gesture instructions shown once per session via `@AppStorage("hasShownGestureInstructions")`

**DraggablePhotoView**
- Gesture handling: swipe up (delete), down (dismiss), left/right (navigate)
- Indicators appear when swipe threshold exceeded (80pt)
- Provides callbacks: `onDelete`, `onNext`, `onPrevious`, `onDismiss`

**Photo Loading Strategy**
- Images loaded via `AssetImage` view component (wraps PHAsset)
- Preloading: current photo ± 3 photos cached using `PHCachingImageManager`
- Screen size handled via `ScreenSizeHelper.screenPhysicalSize`
- Opportunistic delivery mode with network access enabled

### Data Flow

```
User Gesture → View → PhotoManager → PHPhotoLibrary
                      ↓
                 @Published properties update
                      ↓
                   View re-renders
```

### State Management Patterns

- **App Settings**: `@AppStorage` for persistent flags (welcome shown, gesture instructions)
- **Session State**: `@State` in views for UI state (fullscreen mode, current photo)
- **Business Logic**: `@StateObject PhotoManager` in ContentView, passed to child views
- **Navigation**: Manual state-based navigation (no NavigationStack) for custom transitions

### Photo Deletion Flow

1. User swipes up to delete → `addToTrash()` called
2. Photo moved to `pendingDeletionIDs` set, filtered from `displayedPhotos`
3. User can restore from trash or permanently delete via `emptyTrash()`
4. `emptyTrash()` calls `PHPhotoLibrary.performChanges` to actually delete from iOS

### Important Constraints

- Always check `authorizationStatus` before accessing photo library
- Use `hasLoadedOnce` to distinguish loading from empty states
- Gesture instructions overlay is at fullscreen page level, not per-photo
- When returning from fullscreen to list, set `scrollToPhotoID` to maintain position
- PhotoManager must be `@MainActor` since it publishes UI updates

### File Organization

```
CleanMyPhoto/
├── Models/          # Plain data structures (PhotoAsset, PhotoSection)
├── ViewModels/      # PhotoManager (business logic)
├── Views/
│   ├── Components/  # Reusable UI (PhotoCell)
│   └── [Screens]    # ContentView, PhotoListView, DraggablePhotoView, TrashView, WelcomePage
├── Extensions/      # PHAsset+Image
├── Resources/       # CleanMyPhotoApp (app entry)
└── Utils/           # ScreenSizeHelper, etc.
```
