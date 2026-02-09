# CleanMyPhoto - MVVM 架构说明

## 项目结构

```
CleanMyPhoto/
├── Models/                      # 数据模型层
│   ├── PhotoAsset.swift        # 照片资源模型
│   └── PhotoSection.swift      # 照片分组模型
│
├── Views/                       # 视图层
│   ├── Components/             # 可复用的 UI 组件
│   │   └── PhotoCell.swift     # 照片单元格组件
│   ├── ContentView.swift       # 主视图（列表和全屏浏览）
│   ├── PhotoListView.swift     # 照片列表视图
│   ├── DraggablePhotoView.swift # 可拖拽照片全屏视图
│   └── TrashView.swift         # 回收站视图
│
├── ViewModels/                  # 视图模型层
│   └── PhotoManager.swift      # 照片管理器（业务逻辑）
│
├── Extensions/                  # 扩展
│   └── PHAsset+Image.swift     # PHAsset 图片加载扩展
│
├── Resources/                   # 资源文件
│   └── CleanMyPhotoApp.swift   # App 入口文件
│
└── Assets.xcassets/            # 图片资源
```

## MVVM 架构说明

### Model（模型层）
负责数据结构定义，不包含任何业务逻辑。

**文件：**
- `PhotoAsset.swift`: 照片资源模型，封装 PHAsset
- `PhotoSection.swift`: 照片分组模型，用于按月份显示

### View（视图层）
负责 UI 展示和用户交互，通过 `@ObservedObject` 或 `@StateObject` 与 ViewModel 通信。

**文件：**
- `ContentView.swift`: 主视图，处理列表和全屏模式的切换
- `PhotoListView.swift`: 照片列表网格视图
- `DraggablePhotoView.swift`: 全屏照片浏览，支持手势操作
- `TrashView.swift`: 回收站视图
- `Components/PhotoCell.swift`: 可复用的照片单元格组件

### ViewModel（视图模型层）
负责业务逻辑和数据处理，通过 `@Published` 属性向 View 发布数据变化。

**文件：**
- `PhotoManager.swift`:
  - 照片加载和分页
  - 照片分组（按月份）
  - 回收站管理
  - 图片预加载和缓存

## 数据流向

```
用户操作 → View → ViewModel → Model
              ↓         ↑
           更新 UI  ← 数据变化
```

## 设计原则

1. **单一职责**: 每个类只负责一个功能
2. **依赖注入**: View 通过构造函数注入 ViewModel
3. **响应式**: 使用 `@Published` 和 `@ObservedObject` 实现数据绑定
4. **可测试性**: ViewModel 独立于 View，便于单元测试
5. **可复用性**: 组件化的 UI 元素（如 PhotoCell）可以在不同视图中复用
