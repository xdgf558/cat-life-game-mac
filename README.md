# 打工养猫日记 · Mac

原生 Mac 养猫游戏，采用 SwiftUI 与 SpriteKit，在本机保存进度。

**当前状态：**1.4.2（84）准备中，等待审查和手动验收。Steam 接入后续进行。

## 运行

需要 macOS 14+、支持 Swift 6 的 Xcode 和 Git LFS。在开发分支执行：

```sh
git lfs install
git lfs pull
python3 -B scripts/check_runtime_assets.py
open CatLifeMac.xcodeproj
```

选择 `CatLifeMac` scheme 和 `My Mac` 即可构建；该方案用于现有非沙盒构建。`CatLifeMac-AppStore` scheme 用于沙盒运行与 App Store 归档。新增源码后用 `ruby scripts/generate_project.rb` 更新工程（需要 `xcodeproj` Ruby gem）。

App Store 版使用独立的沙盒存档。首次启动可选择旧版存档找回进度，也可稍后在存档管理中导入；原有存档不会被移动或删除，窗口和快捷键设置可能需重新调整。

将 `CATLIFE_BUILD_CACHE` 设为项目约定的 Mac 编译缓存子目录后，可运行 `scripts/check_appstore_build.sh` 检查 App Store 构建；脚本不会启动游戏或运行测试。

后续 Mac 功能、修复和发布统一在本仓库提交。

## 支持

Mac 版问题反馈与隐私咨询：[brodstem@protonmail.com](mailto:brodstem@protonmail.com)。[App Store 版隐私政策](PRIVACY.md)。
