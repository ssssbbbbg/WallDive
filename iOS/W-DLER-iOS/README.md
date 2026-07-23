# WallDive iOS

WallDive iOS 是面向 iPhone 与 iPad 的原生 SwiftUI 客户端，最低支持 iOS 17。

## 功能

- Wallhaven 搜索与连续瀑布流
- 最新、热门、随机浏览模式
- 动漫、照片、横屏与竖屏筛选
- 高质量详情预览与沉浸式缩放
- 本地收藏、用户订阅与标签关注
- 长按多选与批量下载
- 下载队列、失败重试与完成反馈
- 原图直接保存到系统相册
- 中文、英文及跟随系统外观

## 真机运行

1. 使用 Xcode 打开 `W-DLER-iOS.xcodeproj`
2. 选择 `W-DLER-iOS` Scheme
3. 在 Signing & Capabilities 中选择自己的开发团队
4. 连接 iPhone 或 iPad 并点击 Run

也可以从仓库根目录运行：

```bash
DEVELOPMENT_TEAM=你的TeamID ./Scripts/install_ios_device.sh 你的设备UDID
```
