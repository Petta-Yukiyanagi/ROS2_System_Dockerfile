FROM ghcr.io/petta-yukiyanagi/ros_humble_lab:latest

ENV DEBIAN_FRONTEND=noninteractive

# =========================================================
# 基本ツール / Java / X11 / フォント / ROSビルド系
# =========================================================
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      openjdk-17-jre \
      git \
      wget \
      unzip \
      x11-apps \
      fonts-noto-cjk \
      build-essential \
      cmake \
      python3-colcon-common-extensions \
      python3-rosdep \
    && rm -rf /var/lib/apt/lists/*

# =========================================================
# 開発・GUI用ユーザー作成（VS Code / X11 両対応）
# =========================================================
RUN useradd -m -u 1000 -s /bin/bash user

# =========================================================
# Nav2（自律移動用）
# =========================================================
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ros-humble-navigation2 \
      ros-humble-nav2-bringup \
    && rm -rf /var/lib/apt/lists/*

# =========================================================
# rosdep 初期化
# =========================================================
RUN rosdep init || true && rosdep update

# =========================================================
# Roomba / Create 制御ノード
# =========================================================
WORKDIR /opt
RUN mkdir -p roomba_ws/src

WORKDIR /opt/roomba_ws/src
RUN git clone --depth 1 https://github.com/AutonomyLab/create_robot.git

WORKDIR /opt/roomba_ws
RUN /bin/bash -c "source /opt/ros/humble/setup.bash && \
    rosdep install --from-paths src --ignore-src -r -y && \
    colcon build --symlink-install"

# =========================================================
# YDLidar SDK（公式）
# =========================================================
WORKDIR /opt
RUN git clone https://github.com/YDLIDAR/YDLidar-SDK.git

WORKDIR /opt/YDLidar-SDK/build
RUN cmake .. && make -j$(nproc) && make install
RUN ldconfig

# =========================================================
# YDLidar ROS2 Driver（Humble対応）
# =========================================================
WORKDIR /opt/ydlidar_ws/src
RUN git clone -b humble-support https://github.com/Petta-Yukiyanagi/ydlidar_ros2_driver.git

WORKDIR /opt/ydlidar_ws
RUN /bin/bash -c "source /opt/ros/humble/setup.bash && \
    rosdep install --from-paths src --ignore-src -r -y && \
    colcon build --symlink-install"

# =========================================================
# CAT UI（Java / Processing）
# =========================================================
WORKDIR /opt/catui
RUN git clone --depth 1 https://github.com/Petta-Yukiyanagi/CAT-UI-ROS2node.git

WORKDIR /opt/catui/CAT-UI-ROS2node
RUN chmod +x CAT-UI

# =========================================================
# CAT UI IPC ディレクトリの権限調整（重要）
# =========================================================
RUN mkdir -p /opt/catui/CAT-UI-ROS2node/data/ipc && \
    chmod 1777 /opt/catui/CAT-UI-ROS2node/data/ipc

# =========================================================
# 自作 ROS2 ワークスペース（catui_bridge を clone）
# =========================================================
RUN mkdir -p /opt/ros2_ws/src && \
    git clone --depth 1 https://github.com/Petta-Yukiyanagi/CAT-UI-ROS2bridge-node.git \
      /opt/ros2_ws/src/catui_bridge && \
    chmod -R a+rwx /opt/ros2_ws

# =========================================================
# UI + ROS2 起動スクリプト（ros2_ws 初回ビルドのみ）
# =========================================================
RUN printf '%s\n' \
'#!/usr/bin/env bash' \
'set -eo pipefail' \
'' \
'echo "[INFO] run-catui started"' \
'' \
'# ==========================' \
'# ROS 環境' \
'# ==========================' \
'source /opt/ros/humble/setup.bash' \
'source /opt/roomba_ws/install/setup.bash' \
'source /opt/ydlidar_ws/install/setup.bash' \
'' \
'# ==========================' \
'# 自作 ros2_ws（初回のみ build）' \
'# ==========================' \
'if [ -d /opt/ros2_ws/src ]; then' \
'  cd /opt/ros2_ws' \
'  if [ ! -f /opt/ros2_ws/install/setup.bash ]; then' \
'    echo "[INFO] ros2_ws detected: first build"' \
'    colcon build --symlink-install' \
'  else' \
'    echo "[INFO] ros2_ws already built: skip build"' \
'  fi' \
'  source /opt/ros2_ws/install/setup.bash' \
'else' \
'  echo "[WARN] ros2_ws not found: skipping"' \
'fi' \
'' \
'# ==========================' \
'# CAT UI 起動（node / launch は後で）' \
'# ==========================' \
'cd /opt/catui/CAT-UI-ROS2node' \
'exec ./CAT-UI' \
> /usr/local/bin/run-catui && chmod +x /usr/local/bin/run-catui

# =========================================================
# 常駐
# =========================================================
CMD ["/usr/local/bin/run-catui"]