# cat_robot_bringup

このリポジトリは、Cat Robot の **ROS 2 システム全体の起動（bringup）定義**を管理するためのものです。

ROS 2 の launch ファイルを用いて、  
UI・センサ・自己位置推定・局所ナビゲーション（障害物回避）・モータ制御を  
**1コマンドで起動可能**にします。

---

## このリポジトリの役割

本リポジトリは、Cat Robot システムにおける  
**起動司令塔（bringup レイヤ）** です。

- ノードの実装は含みません
- 「どのノードを、どの構成で起動するか」だけを定義します

---

## 起動対象（ラズパイ側）

本 bringup では、以下のノード群を **Raspberry Pi 側で起動**します。

### センサ・制御系
- LiDAR ドライバ（`/scan` を publish）
- Roomba ドライバ（`/cmd_vel` を受信してモータ制御）

### 自己位置推定
- SLAM Toolbox（localization モード）
  - 地図は生成しない
  - 既存地図を用いた自己位置推定のみを行う

### ナビゲーション（最小構成）
- Nav2 Controller Server
- Local Costmap
- 障害物回避および `/cmd_vel` 生成

※ Global Planner / BT Navigator / map_server は起動しません

### UI 連携
- catui_bridge
- JSON は `ipc/broadcast` ディレクトリに書き込まれます

---

## 起動対象に含まれないもの

以下は **本リポジトリでは起動しません**。

- 地図生成（SLAM の mapping モード）
- 地図保存（map_saver）
- Global Planner
- BT Navigator（目的地管理）
- Nav2 フルスタック
- Dockerfile / OS 環境設定

これらは別の PC / WSL / Docker 環境で起動する想定です。

---

## システム構成イメージ
```
┌──────────────────────────────────────────┐
│              Raspberry Pi                │
│        (Real-time / Low latency)         │
│                                          │
│  ┌───────────────┐                       │
│  │ LiDAR Driver  │───▶ /scan ─────────┐ │
│  └───────────────┘                     │ │
│                                        │ │
│  ┌───────────────────────────────┐     │ │
│  │ SLAM Toolbox (Localization)    │◀────┘ │
│  │  - 自己位置推定のみ              │  /tf │
│  │  - 地図生成なし                  │     │
│  └───────────────────────────────┘     │
│                                        │
│  ┌───────────────────────────────┐     │
│  │ Nav2 Controller (Local)        │◀── /scan
│  │  - 障害物回避                   │
│  │  - cmd_vel 生成                │
│  └───────────────────────────────┘     │
│               │                         │
│            /cmd_vel                     │
│               ▼                         │
│  ┌────────────────┐                    │
│  │ create_driver  │──▶ Motors           │
│  └────────────────┘                    │
│                                        │
│  ┌────────────────┐                    │
│  │ catui_bridge   │──▶ IPC (JSON)       │
│  └────────────────┘                    │
└──────────────────────────────────────────┘
                ▲
                │  /scan, /tf, map
                │  (Network / DDS)
                ▼
┌──────────────────────────────────────────┐
│                 PC / WSL                 │
│        (Heavy compute / Planning)        │
│                                          │
│  ┌───────────────────────────────┐       │
│  │ SLAM (Mapping)                 │       │
│  │  - 地図生成                    │       │
│  └───────────────────────────────┘       │
│                │                         │
│              /map                        │
│                ▼                         │
│  ┌───────────────────────────────┐       │
│  │ Global Planner                 │       │
│  │  - 経路計画                    │       │
│  └───────────────────────────────┘       │
│                │                         │
│  ┌───────────────────────────────┐       │
│  │ BT Navigator                  │       │
│  │  - 目的地管理 / 状態遷移       │       │
│  └───────────────────────────────┘       │
│                                          │
│  ┌───────────────────────────────┐       │
│  │ RViz                          │       │
│  │  - 可視化                     │       │
│  └───────────────────────────────┘       │
└──────────────────────────────────────────┘
```

制御系は遅延に弱いためラズパイ側に集約し、  
重い計算や意思決定は外部計算機に分離します。

---

## 使用方法

### 通常起動（全機能有効）

```bash
ros2 launch cat_robot_bringup system.launch.py
```
一部機能を無効化して起動

LiDAR を使わない場合：
```bash
ros2 launch cat_robot_bringup system.launch.py use_lidar:=false
```
Nav2 Controller を使わない場合（手動制御用）：
```bash
ros2 launch cat_robot_bringup system.launch.py use_nav2_controller:=false
```
UI を起動しない場合：
```bash
ros2 launch cat_robot_bringup system.launch.py use_ui:=false
```
IPC 仕様（UI 連携）

UI との連携は ファイル IPC（JSON） により行います。
```
/opt/catui/CAT-UI-ROS2node/data/ipc/
└─ broadcast/
   └─ ui_command.json
```
ROS 2 → UI への一方向通信

UI 側は broadcast ディレクトリを監視

関連リポジトリ

ROS2_System_Dockerfile
Cat Robot 実行環境（Docker / ROS 2）

catui_bridge
ROS 2 と UI 間の IPC ブリッジノード

CAT-UI-ROS2node
表情・テキスト表示を行う UI アプリケーション