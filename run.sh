#!/usr/bin/env bash
set -e

# ============================================================
# Cat Robot System Launcher
# - Docker build (if needed)
# - Docker run
# - ROS2 + Roomba + YDLidar + CAT UI
# - X11 GUI 対応（ダブルクリック起動）
# ============================================================

echo "======================================="
echo "  Cat Robot System Launcher"
echo "======================================="

# ============================================================
# GUI ユーザー・DISPLAY 自動検出
# ============================================================

# GUI セッションのユーザー（desktop起動対応）
GUI_USER=$(logname 2>/dev/null || whoami)

# HOME ディレクトリ取得
GUI_HOME=$(getent passwd "$GUI_USER" | cut -d: -f6)

# DISPLAY（Raspberry Pi OS は :0）
export DISPLAY=:0

# XAUTHORITY 自動設定
if [ -f "$GUI_HOME/.Xauthority" ]; then
  export XAUTHORITY="$GUI_HOME/.Xauthority"
else
  echo "[WARN] .Xauthority not found for user: $GUI_USER"
fi

echo "[INFO] GUI_USER=$GUI_USER"
echo "[INFO] DISPLAY=$DISPLAY"
echo "[INFO] XAUTHORITY=$XAUTHORITY"

# ============================================================
# Docker 設定
# ============================================================

IMAGE="catui:latest"
CONTAINER="cat-iot-robot"

# ============================================================
# X11 アクセス許可（Docker → ホストGUI）
# ============================================================

# DISPLAY が有効な状態で xhost 実行
if command -v xhost >/dev/null 2>&1; then
  xhost +si:localuser:docker >/dev/null 2>&1 || true
else
  echo "[WARN] xhost not found"
fi

# ============================================================
# Docker image build（なければ）
# ============================================================

if ! docker image inspect ${IMAGE} >/dev/null 2>&1; then
  echo "[INFO] Docker image not found. Building..."
  docker build -t ${IMAGE} .
else
  echo "[INFO] Docker image found."
fi

# ============================================================
# 既存コンテナ削除
# ============================================================

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  echo "[INFO] Removing existing container..."
  docker rm -f ${CONTAINER} >/dev/null
fi

# ============================================================
# USB デバイス検出（Roomba）
# ============================================================

USB_DEVICE=""

if [ -e /dev/ttyUSB0 ]; then
  USB_DEVICE="/dev/ttyUSB0"
elif [ -e /dev/ttyUSB1 ]; then
  USB_DEVICE="/dev/ttyUSB1"
else
  echo "[WARN] No /dev/ttyUSB* found. Roomba may not be connected."
fi

if [ -n "$USB_DEVICE" ]; then
  echo "[INFO] USB device detected: $USB_DEVICE"
fi

# ============================================================
# Docker run（UI起動込み）
# ============================================================

echo "[INFO] Starting container..."

docker run -d \
  --name ${CONTAINER} \
  --privileged \
  ${USB_DEVICE:+--device=$USB_DEVICE} \
  -e DISPLAY=${DISPLAY} \
  -e XAUTHORITY=${XAUTHORITY} \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v ${XAUTHORITY}:${XAUTHORITY}:ro \
  ${IMAGE} \
  /usr/local/bin/run-catui

echo "======================================="
echo " Cat Robot System started."
echo " UI should now be visible."
echo "======================================="
echo
echo "Press ENTER to close this window."
read