# Tactical Protocol — Godot Edition

网页版 [tactical-protocol](https://github.com/HecreReed/tactical-protocol) 的 **Godot 4.6** 原生移植版。
当前同步 29 名特工、116 个标准技能槽和 16 张地图；运行时完全使用本地 GDScript、官方肖像与技能图标。

## 运行

用 Godot 4.6+ 打开本项目目录，F5 运行；或命令行：

```bash
godot --path .
```

无头冒烟测试（自动开局跑对局并输出状态）：

```bash
TP_AUTOSTART=yiji godot --headless --path . --quit-after 12000
```

## 已实现（对齐网页版）

- **16 张地图同步**：遗迹 / 三塔 / 裂峡 / 天港 / 雪峰 / 熔城 / 古庙 / 环街 / 四象 / 重庆 / 天枢 / 云雀 / 朝门 / 赤练 / 京城 / 龙脊
  —— 房间/走廊/内墙/高台/四向楼梯/桥梁/箱子/屋顶（不可站立）/包点/出生点/购买阶段光幕，全部由共享 JSON 数据生成
- **5v5 炸弹模式**：购买 20s → 交战 100s → 下包 4s / 45s 引爆 / 拆包 7s → 先赢 13 回合，12 回合攻防互换，连败经济补偿
- **FPS 手感**：WASD/跳/蹲/Shift 静步、散布+后座+首发精准、ADS（狙击右键切换开镜）、R 换弹、B 买枪（16 把武器全数据移植）
- **AI**：NavigationAgent3D 寻路 + 状态机（推进/执行/下包/驻守/拆包/捡包）、防守方购买阶段就位、视线交战、成长精度、进度看门狗防卡死
- **29 名特工、116 个技能槽**：官方 C/Q/E/X 数据、肖像、技能图标和显式处理器由同步目录驱动；玩家与 AI 共用验证、扣费、冷却和重施路径
- **HUD**：血量/护甲/弹药/金钱/计时/比分/横幅/准星/受击红晕，以及技能充能、冷却、资源、重施、控制和死后施法状态

## 在线试玩（Web 版）

**https://hecrereed.github.io/tactical-protocol-godot/** （GitHub Actions 自动构建，单线程 WASM 导出）

## 相对网页版的加强

- 真实 3D 导航网格（体素烘焙）替代网格导航
- MSAA 抗锯齿 + 程序化天空 + 距离雾
- 命中部位按真实命中点高度判定（头/身/腿）

## 已对齐清单（本版）

- [x] 29 名官方特工与 116 个技能槽（统一执行器 + AI 共用施法校验）
- [x] 商店买卖：武器/护甲/技能充能 **右键卖回**（同回合全额退款）
- [x] 小地图（墙体/敌我/包点/炸弹实时绘制）、击杀条、Tab 记分板、购买阶段战斗报告
- [x] 掉落武器 = **真刚体物理**（爆炸冲量可推动），玩家 F 拾取、AI 弹尽自动捡枪、无枪拼刀
- [x] 手雷 = RigidBody 真实弹跳（PhysicsMaterial 弹性），死亡布娃娃（冲量+扭矩）
- [x] 烟雾双层机制：AI 视线专用遮断层（子弹可穿）+ 玩家进烟全屏遮罩
- [x] GPU 粒子（枪口/命中/爆炸/传送）、Glow 泛光、ACES 色调映射、程序化天空+距离雾
- [x] 光幕独立碰撞层（不进导航），AStarGrid2D 网格导航（移植网页版方案，C++ 加速）

## 结构

```
project.godot          输入映射 / 渲染配置
scenes/Main.tscn       入口场景
scripts/main.gd        启动器 + 战斗系统（射线/投掷物/特效）
scripts/map_builder.gd 地图构建（几何/碰撞/导航烘焙/光幕/点位）
scripts/match_mgr.gd   回合循环 / 经济 / 下包拆包 / 胜负
scripts/player.gd      第一人称控制器
scripts/bot_ai.gd      AI 状态机 + 导航 + 交战
scripts/weapons.gd     武器数据表
scripts/hud.gd         HUD
data/agents.json       29 名特工和 116 个技能槽的同步目录
data/maps.json         16 张地图数据（网页版导出，两版同步）
assets/agents/         本地官方肖像与技能图标
tools/sync_from_csgo.mjs  从相邻 csgo 工作树只读同步数据与媒体
```
