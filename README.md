# Cat Robot System  
**ROS2 + Roomba + Nav2 + YDLidar + CAT UI (Java / Processing)**

このリポジトリは、  
**Roomba（600系） + ROS2 Humble + Nav2 + YDLidar + Java/Processing UI** を  
**Docker 1コンテナ**で統合したロボットシステムです。


---

## 特徴

- Docker を直接操作する必要なし
- ターミナル操作は不要
- **デスクトップのダブルクリックだけで起動**
- 環境構築・依存関係はすべて Docker に封じ込め
- 起動するたびに **クリーンな状態** で立ち上がる

---

## 全体構成（概要）

```
Host OS (Raspberry Pi OS / Ubuntu + X11)
│
├─ Desktop
│   └─ cat-robot.desktop（ダブルクリック）
│        ↓
│      run.sh
│        ↓
├─ Docker
│   └─ catui:latest
│       ├─ ROS2 Humble
│       ├─ Roomba(Create / Roomba600) Driver
│       ├─ Nav2
│       ├─ YDLidar SDK + ROS2 Driver
│       └─ CAT UI (Java / Processing)
│
└─ USB
    ├─ /dev/ttyUSB* (Roomba)
    └─ /dev/ttyUSB* (YDLidar)
```

---

## Docker コンテナの中身

このシステムは **1つの Docker イメージ**で構成されています。

### ベース
- ROS2 Humble
- Ubuntu 22.04 ベース

### 含まれる機能

- **ROS2**
  - ros-humble-desktop 相当
  - colcon / rosdep

- **Roomba / Create 制御**
  - `create_robot`（AutonomyLab）
  - `/cmd_vel` による実機制御

- **Nav2**
  - `nav2_bringup`
  - 自律移動用スタック一式

- **YDLidar**
  - YDLidar SDK
  - ROS2 driver（Humble対応）

- **CAT UI**
  - Java + Processing 製 UI
  - ROS2 と連携して表情・表示を制御

---

---

## 起動方式について（重要）

### Dockerをインストールする



### ダブルクリック起動時の挙動

デスクトップから起動すると、以下が **毎回自動で実行**されます。

1. Docker イメージの存在確認（なければ自動ビルド）  
2. 既存コンテナがあれば削除  
3. 新しいコンテナを作成  
4. ROS2 環境を source  
5. CAT UI（Java / Processing）を起動  

👉 **起動するたびに Docker コンテナは作り直されます**

---

## 使い方

① システムの更新と依存ツールのインストール
DockerおよびGUI選択ツール（Zenity）をインストールします。ターミナルを開いて以下を貼り付けてください。


### Dockerのインストール
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
```
### ユーザー権限の設定（Dockerをsudoなしで動かすため）
```bash
sudo usermod -aG docker $USER
sudo usermod -aG dialout $USER
```
### GUIツールのインストール
```bash
sudo apt-get update
sudo apt-get install -y zenity x11-xserver-utils
```
### 設定を反映させるため、一度再起動してください
```bash
sudo reboot
```
### ① リポジトリを取得する

```bash
git clone https://github.com/Petta-Yukiyanagi/ROS2_System_Dockerfile.git
cd ROS2_System_Dockerfile
```

※ 以下の場所に配置されることを前提にしています。

```
/home/ユーザー名/ROS2_System_Dockerfile
```

👉 場所を変えないことを推奨します  
（.desktop ファイルを編集せずに済みます）

---

### ② 実行権限を付与する

```bash
chmod +x run.sh
chmod +x desktop/cat-robot.desktop
```

---

### ③ デスクトップに起動アイコンを配置する

```bash
cp desktop/cat-robot.desktop ~/Desktop/
```

---

### ④ 起動する（唯一の起動方法）

1. Desktop 上の **「Cat Robot System」** をダブルクリック  
2. 初回のみ「信頼して実行しますか？」と聞かれたら  
   → **「信頼する」** を選択  
3. ターミナルが開き、Docker の起動ログが表示されます  

4. GUIが出てくるので、画面モードとUSBポートを選択します。

5. 数秒後、CAT UI が画面に表示されます  

---

## FAQ

### Q. USBデバイスが1つしか認識されません
Roomba と LiDAR の両方が接続されているか確認してください。システムは安全のため、2つ以上のシリアルデバイスを検出できないとエラーを出す仕様になっています。

---

### Q. Desktop に表示されません

以下を確認してください。

- `~/Desktop/` にコピーしたか  
- `chmod +x` を実行したか  
- ファイルマネージャを再起動、または再ログインしたか  

---

