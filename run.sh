#!/usr/bin/env bash
# エラーが発生した時点で停止し、未定義変数を参照させない設定
set -euo pipefail

# --- 終了時にログを確認できるよう停止する関数 ---
function pause_exit(){
   # スクリプトが正常・異常に関わらず終了時に実行
   echo ""
   echo "======================================="
   echo " 処理が終了しました。ログを確認してください。"
   echo " Enterキーを押すとウィンドウを閉じます。"
   echo "======================================="
   read -r
}
trap pause_exit EXIT

# 実行コマンドのデバッグ表示（配布時はコメントアウトしてもOK）
set -x 
exec 2>&1 

# スクリプト自身の場所を特定し、カレントディレクトリを移動
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ------------------------------------------------------------
# 0. 依存チェック
# ------------------------------------------------------------
command -v docker >/dev/null || { echo "[ERROR] docker が見つかりません"; exit 1; }

# GUIツール必須（毎回選択する方針）
if ! command -v zenity >/dev/null; then
  echo "[ERROR] zenity が見つかりません。毎回選択する設計のため起動できません。"
  exit 1
fi

# X11関連（無い/不要な場合に備える）
HAS_XHOST=0
if command -v xhost >/dev/null; then
  HAS_XHOST=1
fi

# 1. ホスト側でのGUI表示許可（X11がある時だけ）
GUI_MODE=$(zenity --list --title="Cat Robot - Display Mode" \
  --text="使用する画面モードを選択してください" --radiolist \
  --column="選択" --column="モード" \
  TRUE "HDMI（展示・現地）" FALSE "RealVNC（開発・遠隔）" \
  --height=220 --width=360) || exit 1

# ------------------------------------------------------------
# 2. イメージの自動ビルド（イメージがない場合のみ実行）
# ------------------------------------------------------------
LOCAL_IMAGE="catui:latest"

# Dockerfile のあるディレクトリを明示（ここが超重要）
DOCKER_DIR="$HOME/cat-iot-robot-ui"
DOCKERFILE_PATH="$DOCKER_DIR/Dockerfile"

if [ ! -f "$DOCKERFILE_PATH" ]; then
  echo "[ERROR] Dockerfile が見つかりません: $DOCKERFILE_PATH"
  exit 1
fi

if [[ "$(docker images -q "$LOCAL_IMAGE" 2>/dev/null)" == "" ]]; then
  echo "[INFO] 初回起動を検知しました。イメージのビルドを開始します..."
  docker build --no-cache -t "$LOCAL_IMAGE" -f "$DOCKERFILE_PATH" "$DOCKER_DIR" 2>&1 | tee "$SCRIPT_DIR/build.log"
else
  echo "[INFO] ビルド済みイメージ $LOCAL_IMAGE を使用します。"
fi

# ------------------------------------------------------------
# 3. ホスト側での設定選択 (Zenity)
# ------------------------------------------------------------

 # USBデバイスの検出
 TTY_DEVICES=($(ls /dev/ttyUSB* 2>/dev/null || true))
 if [ ${#TTY_DEVICES[@]} -lt 2 ]; then
   zenity --error --text="ttyUSBデバイスが不足しています（RoombaとLiDARの2つが必要です）。"
   exit 1
 fi

 # 各デバイスの選択（キャンセルされたら終了）
 ROOMBA_TTY=$(zenity --list --title="Roomba 接続" --text="Roombaのポートを選択" \
   --column="デバイス" "${TTY_DEVICES[@]}" --height=300) || exit 1

 LIDAR_TTY=$(zenity --list --title="LiDAR 接続" --text="LiDARのポートを選択" \
   --column="デバイス" "${TTY_DEVICES[@]}" --height=300) || exit 1

# 同一デバイス選択チェック
if [ "$ROOMBA_TTY" = "$LIDAR_TTY" ]; then
  zenity --error --text="同じポートは選択できません。別々のデバイスを選んでください。"
  exit 1
fi

# ------------------------------------------------------------
# X11 許可（DockerからGUIを出すために必須）
# ------------------------------------------------------------
if [ "$HAS_XHOST" -eq 1 ]; then
  echo "[INFO] Allowing Docker to access X11"
  xhost +local:docker
fi

# ------------------------------------------------------------
# 4. Docker 起動
# ------------------------------------------------------------
# 既存の同名コンテナがあれば強制削除（名前衝突を回避）
docker rm -f cat_robot_sys 2>/dev/null || true

# --device によるマッピングで、コンテナ内でのリンク作成を不要にしています
DOCKER_X11_ARGS=()
if [ -n "${DISPLAY:-}" ]; then
  DOCKER_X11_ARGS+=( -e DISPLAY="$DISPLAY" -v /tmp/.X11-unix:/tmp/.X11-unix )
else
  echo "[INFO] DISPLAY が無いのでX11マウントをスキップ"
fi

docker run -it --rm \
    --name cat_robot_sys \
    --privileged \
    --net=host \
    -v /dev:/dev \
    -v "$SCRIPT_DIR/ros2_ws:/opt/ros2_ws" \
    -e CAT_MODE="$([[ "$GUI_MODE" == *"HDMI"* ]] && echo "EXHIBITION" || echo "DEVELOPMENT")" \
    -e CAT_DEBUG="$([[ "$GUI_MODE" == *"HDMI"* ]] && echo "0" || echo "1")" \
    --device="$ROOMBA_TTY:/dev/roomba" \
    --device="$LIDAR_TTY:/dev/lidar" \
    "${DOCKER_X11_ARGS[@]}" \
    "$LOCAL_IMAGE"