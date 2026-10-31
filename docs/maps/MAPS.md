# 地图方案与合规（海外版）

## 决定（2026-10-31）
- **全球统一使用 Apple 地图（MapKit / SwiftUI `Map`）**，不接入第三方瓦片，不提供「下载地图 / 离线地图包」功能。
- 当前版本只面向中国以外市场；中国大陆版以后在境内云单独部署（届时另定地图方案：GCJ-02、审图号、持资质的国内地图 SDK）。

## 本次改动（分支 `fix/map-tiles-compliance`）
1. **删除 `MapTileCacheManager`**（及项目引用、`AppCoordinator` 中的实例）。
   它默认使用 OSM 基金会官方瓦片服务器并带「下载此区域」预取——OSMF 政策明确禁止预取与离线使用。
   该组件从未接入任何界面，线上没有发生实际请求；删除后不再存在误接入的风险。
2. **地图上的 Apple 标志与「法律信息（Legal）」链接不再被遮挡。** SwiftUI `Map` 把它们放在左下角，原来有 4 处浮层压在上面：
   | 位置 | 原来 | 现在 |
   |---|---|---|
   | `LocationCardView` 地图卡片的「回到当前位置」按钮 | 左下 | 右下 |
   | `GuardianMemberDetailView` 地址标签 | 左下 | 左上 |
   | `GuardianAlertResponseView` 定位精度标签 | 左下 | 左上 |
   | `GuardianAlertResponseView`「最后已知位置」标签 | 左下 | 左上 |

## Apple 地图使用规则（Apple Developer Program License Agreement 附件 6）
- **不得预取、存储或批量下载地图数据**；只允许系统为性能做的临时缓存（第 2.2、2.5 条）。→ 因此不做离线地图下载。
- **不得遮挡、修改 Apple 地图标志和法律信息链接**。新增地图浮层时避开左下角。
- 地图数据仅用于本 App 的功能（第 1.2 条）。
- 来源：https://developer.apple.com/support/terms/apple-developer-program-license-agreement/

## 对产品的影响
- **无信号时**：地图只显示系统临时缓存过的区域；**轨迹记录、SOS 位置、坐标不受影响**（GPS 不需要网络）。
- 出行守护（户外模式）因此调整为：
  - 无地图时仍显示轨迹线、计划路线、方向与距离、坐标（WGS-84 / 度分秒）。
  - 提供 GPX / KML 导出，用户可在自己的户外 App 中离线查看。
  - 出发前提醒「无信号区域地图可能无法显示」。
- 以后若确有离线地图需求，再评估自建 OSM 矢量瓦片（MapLibre + PMTiles，ODbL 署名）或有离线授权的商业瓦片，需重新立项。
