# 打工养猫日记 · Mac

原生 Mac 养猫游戏，采用 SwiftUI 与 SpriteKit，在本机保存进度。

**当前状态：**0.26.0（71）开发中，等待审查和手动验收。Steam 接入后续进行。

## 运行

需要 macOS 14+、支持 Swift 6 的 Xcode 和 Git LFS。在开发分支执行：

```sh
git lfs install
git lfs pull
python3 -B scripts/check_runtime_assets.py
open CatLifeMac.xcodeproj
```

选择 `CatLifeMac` scheme 和 `My Mac` 即可构建。新增源码后用 `ruby scripts/generate_project.rb` 更新工程（需要 `xcodeproj` Ruby gem）。

后续 Mac 功能、修复和发布统一在本仓库提交。
