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
# ソースコードの展開先（SCRIPT_DIRの隣）
PROJECT_DIR="$(dirname "$SCRIPT_DIR")/cat_robot_project"
REPO_URL="https://github.com/Petta-Yukiyanagi/cat_root_sys_ROS2"

# ------------------------------------------------------------
# 2. GitHub 自動同期（最初の一回を不要にする）
# ------------------------------------------------------------
if [ ! -d "$PROJECT_DIR" ]; then
  echo "[INFO] ソースコードを GitHub から取得(clone)します..."
  git clone "$REPO_URL" "$PROJECT_DIR"
else
  echo "[INFO] 既存のフォルダを最新の状態に更新(pull)します..."
  cd "$PROJECT_DIR" && git pull
fi

# ------------------------------------------------------------
# 3. Docker イメージのビルド
# ------------------------------------------------------------
LOCAL_IMAGE="catui:latest"
echo "[INFO] Dockerイメージを確認・ビルドします..."
# ツール側のDockerfileを使い、プロジェクト側のソースを材料(Context)にする
docker build -t "$LOCAL_IMAGE" -f "$SCRIPT_DIR/Dockerfile" "$PROJECT_DIR"

# ------------------------------------------------------------
# 4. ホスト側での GUI 設定 (Zenity)
# ------------------------------------------------------------
GUI_MODE=$(zenity --list --title="Cat Robot Mode" --text="モード選択" --radiolist \
  --column="選択" --column="モード" TRUE "HDMI" FALSE "VNC" --height=200) || exit 1

TTY_DEVICES=($(ls /dev/ttyUSB* 2>/dev/null || true))
if [ ${#TTY_DEVICES[@]} -lt 2 ]; then
   zenity --error --text="USBデバイス（RoombaとLiDAR）を接続してください。"
   exit 1
fi
ROOMBA_TTY=$(zenity --list --title="Roomba" --text="Port" --column="Device" "${TTY_DEVICES[@]}") || exit 1
LIDAR_TTY=$(zenity --list --title="LiDAR" --text="Port" --column="Device" "${TTY_DEVICES[@]}") || exit 1

# ------------------------------------------------------------
# 5. X11 許可設定（重要：これを入れないと画面が出ません）
# ------------------------------------------------------------
if command -v xhost >/dev/null; then
  echo "[INFO] Allowing Docker to access X11"
  xhost +local:docker >/dev/null 2>&1 || true
fi

# ------------------------------------------------------------
# 6. Docker 起動
# ------------------------------------------------------------
docker rm -f cat_robot_sys 2>/dev/null || true

# X11用の引数を整理
DOCKER_X11_ARGS=()
if [ -n "${DISPLAY:-}" ]; then
  DOCKER_X11_ARGS+=( -e DISPLAY="$DISPLAY" -v /tmp/.X11-unix:/tmp/.X11-unix )
fi

docker run -it --rm \
    --name cat_robot_sys \
    --privileged \
    --net=host \
    -v /dev:/dev \
    "${DOCKER_X11_ARGS[@]}" \
    -e CAT_MODE="$([[ "$GUI_MODE" == "HDMI" ]] && echo "EXHIBITION" || echo "DEVELOPMENT")" \
    -e CAT_DEBUG="$([[ "$GUI_MODE" == "HDMI" ]] && echo "0" || echo "1")" \
    --device="$ROOMBA_TTY:/dev/roomba" \
    --device="$LIDAR_TTY:/dev/lidar" \
    "$LOCAL_IMAGE"