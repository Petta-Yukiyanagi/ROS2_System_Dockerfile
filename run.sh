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

# 1. ホスト側でのGUI表示許可
xhost +local:docker > /dev/null

# ------------------------------------------------------------
# 2. イメージの自動ビルド（イメージがない場合のみ実行）
# ------------------------------------------------------------
LOCAL_IMAGE="cat_robot_local"

if [[ "$(docker images -q $LOCAL_IMAGE 2> /dev/null)" == "" ]]; then
  echo "[INFO] 初回起動を検知しました。イメージのビルドを開始します..."
  # Dockerfile がカレントディレクトリにある前提
  docker build -t "$LOCAL_IMAGE" .
else
  echo "[INFO] ビルド済みイメージ $LOCAL_IMAGE を使用します。"
fi

# ------------------------------------------------------------
# 3. ホスト側での設定選択 (Zenity)
# ------------------------------------------------------------
# 表示モードの選択
GUI_MODE=$(zenity --list --title="Cat Robot - Display Mode" \
  --text="使用する画面モードを選択してください" --radiolist \
  --column="選択" --column="モード" \
  TRUE "HDMI（展示・現地）" FALSE "RealVNC（開発・遠隔）" \
  --height=220 --width=360 2>/dev/null || echo "HDMI")

# USBデバイスの自動検出
TTY_DEVICES=($(ls /dev/ttyUSB* 2>/dev/null || true))
if [ ${#TTY_DEVICES[@]} -lt 2 ]; then
  zenity --error --text="ttyUSBデバイスが不足しています（RoombaとLiDARの2つが必要です）。"
  exit 1
fi

# 各デバイスの選択
ROOMBA_TTY=$(zenity --list --title="Roomba 接続" --text="Roombaのポートを選択" \
  --column="デバイス" "${TTY_DEVICES[@]}" --height=300)
[ -z "$ROOMBA_TTY" ] && exit 1

LIDAR_TTY=$(zenity --list --title="LiDAR 接続" --text="LiDARのポートを選択" \
  --column="デバイス" "${TTY_DEVICES[@]}" --height=300)
[ -z "$LIDAR_TTY" ] && exit 1

# 同一デバイス選択チェック
if [ "$ROOMBA_TTY" = "$LIDAR_TTY" ]; then
  zenity --error --text="同じポートは選択できません。別々のデバイスを選んでください。"
  exit 1
fi

# ------------------------------------------------------------
# 4. Docker 起動
# ------------------------------------------------------------
# 既存の同名コンテナがあれば強制削除（名前衝突を回避）
docker rm -f cat_robot_sys 2>/dev/null || true

# --device によるマッピングで、コンテナ内でのリンク作成を不要にしています
docker run -it --rm \
    --name cat_robot_sys \
    --privileged \
    --net=host \
    -e DISPLAY="$DISPLAY" \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v /dev:/dev \
    -v "$SCRIPT_DIR/ros2_ws:/opt/ros2_ws" \
    -e CAT_MODE="$([[ "$GUI_MODE" == *"HDMI"* ]] && echo "EXHIBITION" || echo "DEVELOPMENT")" \
    -e CAT_DEBUG="$([[ "$GUI_MODE" == *"HDMI"* ]] && echo "0" || echo "1")" \
    --device="$ROOMBA_TTY:/dev/roomba" \
    --device="$LIDAR_TTY:/dev/lidar" \
    "$LOCAL_IMAGE"