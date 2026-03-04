#!/usr/bin/env bash
# エラー発生時に停止
set -euo pipefail

# --- 終了時にログを確認できるよう停止する関数 ---
function pause_exit(){
   echo -e "\n=======================================\n 終了しました。Enterで閉じます。\n======================================="
   read -r
}
trap pause_exit EXIT

# 1. パスの設定
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")/cat_robot_project"
REPO_URL="https://github.com/Petta-Yukiyanagi/cat_root_sys_ROS2"

# 2. GitHub 自動同期
if [ ! -d "$PROJECT_DIR" ]; then
  echo "[INFO] ソースコードを GitHub から取得(clone)します..."
  git clone "$REPO_URL" "$PROJECT_DIR"
else
  echo "[INFO] 既存のフォルダを最新の状態に更新(pull)します..."
  cd "$PROJECT_DIR" && git pull
fi

# 3. Docker イメージのビルド
LOCAL_IMAGE="catui:latest"
echo "[INFO] Dockerイメージを確認・ビルドします..."
docker build -t "$LOCAL_IMAGE" -f "$SCRIPT_DIR/Dockerfile" "$PROJECT_DIR"

# 4. ホスト側での GUI 設定 (Zenity) & USB自動判別
GUI_MODE=$(zenity --list --title="Cat Robot Mode" --text="モード選択" --radiolist \
  --column="選択" --column="モード" TRUE "HDMI" FALSE "VNC" --height=200) || exit 1

echo "[INFO] USBデバイスを by-id で取得します..."

ROOMBA_TTY=$(ls /dev/serial/by-id/*FT232R* 2>/dev/null | head -n 1 || true)
LIDAR_TTY=$(ls /dev/serial/by-id/*CP2102* 2>/dev/null | head -n 1 || true)

# 片方または両方見つからない場合のフォールバック
if [ -z "$ROOMBA_TTY" ] || [ -z "$LIDAR_TTY" ]; then
   TTY_DEVICES=($(ls /dev/ttyUSB* 2>/dev/null || true))
   if [ ${#TTY_DEVICES[@]} -gt 0 ]; then
      zenity --info --text="自動検出に失敗、または片方が未接続です。手動で選んでください。" --timeout=3
      ROOMBA_TTY=$(zenity --list --title="Roomba" --text="Roombaのポートを選択 (無い場合はそのままOK)" --column="Device" "${TTY_DEVICES[@]}" "") || ROOMBA_TTY=""
      LIDAR_TTY=$(zenity --list --title="LiDAR" --text="LiDARのポートを選択 (無い場合はそのままOK)" --column="Device" "${TTY_DEVICES[@]}" "") || LIDAR_TTY=""
   fi
fi

# 未定義エラー回避のために空ならダミー(/dev/null)を入れる
: "${ROOMBA_TTY:=/dev/null}"
: "${LIDAR_TTY:=/dev/null}"

echo "[INFO] Detected Roomba: $ROOMBA_TTY"
echo "[INFO] Detected LiDAR: $LIDAR_TTY"

# ポートの初期化
echo "[INFO] ポートを初期化中..."
sudo fuser -k "$ROOMBA_TTY" "$LIDAR_TTY" 2>/dev/null || true
sudo setfacl -b "$ROOMBA_TTY" "$LIDAR_TTY" 2>/dev/null || true
sudo chmod 666 "$ROOMBA_TTY" "$LIDAR_TTY" 2>/dev/null || true

# 5. X11 許可設定
if command -v xhost >/dev/null; then
  echo "[INFO] Allowing Docker to access X11"
  xhost +local:docker >/dev/null 2>&1 || true
fi

# 6. Docker 起動
docker rm -f cat_robot_sys 2>/dev/null || true

DOCKER_X11_ARGS=()
if [ -n "${DISPLAY:-}" ]; then
  DOCKER_X11_ARGS+=( -e DISPLAY="$DISPLAY" -v /tmp/.X11-unix:/tmp/.X11-unix )
fi

# ★【修正点2】構文エラー回避のため、変数を事前に確定
if [ "$GUI_MODE" == "HDMI" ]; then
    CAT_MODE_VAL="EXHIBITION"
    CAT_DEBUG_VAL="0"
else
    CAT_MODE_VAL="DEVELOPMENT"
    CAT_DEBUG_VAL="1"
fi

echo "[INFO] システムを起動します。ログが出たらルンバを連打して起こしてください。"

docker run -it --rm \
    --name cat_robot_sys \
    --privileged \
    --net=host \
    "${DOCKER_X11_ARGS[@]}" \
    -e CAT_MODE="$CAT_MODE_VAL" \
    -e CAT_DEBUG="$CAT_DEBUG_VAL" \
    -e QT_X11_NO_MITSHM=1 \
    ${ROOMBA_TTY:+--device="$ROOMBA_TTY:/dev/roomba"} \
    ${LIDAR_TTY:+--device="$LIDAR_TTY:/dev/lidar"} \
    "$LOCAL_IMAGE"