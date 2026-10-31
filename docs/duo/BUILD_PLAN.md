# iPhone Duo 构建与发布计划

2026-10-31 · 配合 [DUO_PLAN.md](DUO_PLAN.md)（功能与设计）。本文件只讲：用什么编译、怎么测试、怎么出截图、什么时候发布。

---

## 一、现状（已核实）

| 项目 | 现在 | 问题 |
|---|---|---|
| 本机 Xcode | 27.0 和 27.1（`/Applications/Xcode.app`、`Xcode-27.1.app`）；没有 Xcode 26 | — |
| CI（`.github/workflows/ci.yml`） | `runs-on: macos-15` + **Xcode 16**，测试用 iPhone 16 模拟器；push 到 main 自动打包上传 TestFlight | **Xcode 16 的包已无法上传**：2026-04-28 起 App Store Connect 只接受 Xcode 26 及以上编译的包（[Apple](https://developer.apple.com/news/upcoming-requirements/)）。CI 的 TestFlight 任务目前必然失败 |
| `project.yml` | `xcodeVersion: "16.0"`，Firebase `from: 11.0.0` | 与实际开发环境不一致 |
| 部署目标 | iOS 17.0，Swift 5.9 | 保持不变 |
| 版本 | 1.0.0 (32) | — |

**用哪个 Xcode 编译，决定 App 在 Duo 上的样子：**

| 编译用的 SDK | Duo 内屏表现 |
|---|---|
| iOS 26 及更早 | 兼容模式：中间一个普通 iPhone 大小的窗口，四周留空。最安全，但显得「没适配」 |
| iOS 27.0 | 基本铺满内屏（避开状态栏），**现有布局问题会露出来** |
| **iOS 27.1** | 完全铺满、系统栏变侧边竖排。**必须先完成第一阶段适配** |

> 结论：本机只有 Xcode 27，任何新上传的包都会在 Duo 上铺满显示。**在第一阶段（折痕安全布局）合并之前，不要上传新的 TestFlight / App Store 包**；如必须紧急发版，安装 Xcode 26.x 用于该次打包（得到兼容模式）。

---

## 二、编译环境

1. **统一用 Xcode 27.1（iOS 27.1 SDK）。** 部署目标保持 iOS 17；27.1 的新 API 一律 `if #available(iOS 27.1, *)`。
2. **零警告：** 升级后 `UIScreen.main` 等会出废弃警告，第一阶段一并清掉。
3. **Firebase：** 现在锁 `from: 11.0.0`，最新为 13.x。先在 Xcode 27.1 下确认 11.x 编译无警告；升级到 13.x 单独做一个小改动并完整回归（不和 Duo 改动混在一起）。
4. **`project.yml`：** `xcodeVersion` 改为 `"27.1"`，与实际一致。

## 三、CI 改造

| 任务 | 改为 | 说明 |
|---|---|---|
| iOS 构建与测试 | GitHub 的 `xcode-27` 镜像（arm64，macOS 27）+ `xcode-select` 到 Xcode 27.1 | `macos-26` 镜像只有 Xcode 26。`xcode-27` 镜像最新一版是 2026-10-26，**是否已含 27.1 和 iOS 27.1 模拟器（iPhone Duo）尚未确认**，需要在 CI 里先跑一次 `xcodebuild -version` 和 `xcrun simctl list devicetypes` 验证；若没有，用自托管 Mac（本机即可）作为 runner |
| 测试设备 | 增加矩阵：iPhone 17 Pro（iOS 27.0）、**iPhone Duo**（iOS 27.1，外屏）、iPad（iOS 27.0，代替内屏的 regular 布局） | 用同一套测试；见第四节 |
| TestFlight | 同样换成 Xcode 27.1；**加一道门：Duo 截图测试通过才允许上传** | 防止把未适配的版本发出去 |
| 模拟器稳定性 | 每次新建模拟器（`simctl create`），结束删除 | 本地经验：旧模拟器会让测试卡住 |

## 四、测试计划

| 层级 | 内容 | 设备 / 方式 |
|---|---|---|
| 单元测试 | 现有 372 个 + 第一阶段新增（折痕分栏计算、尺寸切换后状态保留） | 三台模拟器都跑 |
| 布局快照 | 主要页面在三种宽度下的截图对比：外屏 466 pt、内屏 669 / 951 pt、分屏约 475 pt；五种语言各一套（法语、日语文字最长） | 新增 Xcode 测试方案 `ShouDeng-Duo.xctestplan`，只在 Duo 和 iPad 上跑 |
| 手动检查清单 | 合上 / 展开 / 半折切换时：输入框文字、选中的家人、SOS 倒计时不丢；SOS 按钮不在折痕上；侧边标签栏位置正确；Touch ID 解锁；侧边 Dynamic Island 的实时活动 | Xcode **Device Hub** 切换姿态（命令行无法折叠模拟器） |
| 真机 | 至少 1 台 iPhone Duo：铰链、半折桌面模式、Touch ID、外屏 Dynamic Island、StandBy | 内部 TestFlight；Duo 目前缺货（交付约 2027 年 1 月），尽早下单 |

## 五、App Store 截图

| 规格 | 尺寸 | 何时需要 |
|---|---|---|
| Duo 外屏 | 1398 × 2034 px | 现在可选；**2027 年 4 月起必需** |
| Duo 内屏 | 2007 × 2853 px | 同上 |

- 代码里已有截图模式（`-screenshot` 启动参数，`Debug/ScreenshotCapture.swift`），扩展为 Duo 两种尺寸 × 五种语言自动出图。
- 外屏截图可直接从模拟器自动生成；内屏需在 Device Hub 展开后截取（或用 iPad 截图仅作内部预览，不可上传）。
- 提供 Duo 截图后可获得「为 iPhone Duo 优化」标识。

## 六、发布节奏

| 版本 | 内容 | 编译 | 时间 |
|---|---|---|---|
| 1.0.x（当前 TestFlight 迭代） | 现有功能修复 | **暂停上传**，等第一阶段合并；紧急情况用 Xcode 26 | 现在 |
| **1.1** | 第一阶段：折痕安全布局、系统标签栏、状态保留、零警告；CI 换到 Xcode 27.1 | Xcode 27.1 | 第一阶段完成后（约 1–1.5 周） |
| 1.2 | 第二阶段：列表 + 详情、SOS 响应双栏、长辈大屏模式 | Xcode 27.1 | 2026 年 12 月 |
| 1.3 | 第三阶段：桌面模式、实时活动 / StandBy、**Duo 截图上架** | Xcode 27.1 | **2027 年 3 月前**（4 月截图强制） |

## 七、需要你处理 / 决定

1. **CI 的 TestFlight 任务**目前因 Xcode 16 无法上传，是否改为 `xcode-27` 镜像或用本机做自托管 runner。
2. 最近的 TestFlight 包是用哪台电脑、哪个 Xcode 打的？如果是本机 Xcode 27.x，Duo 用户现在已经看到铺满的布局。
3. 是否购买一台 iPhone Duo 测试机。
4. 第一阶段合并前若要发版，是否安装 Xcode 26.x 专门打包。
