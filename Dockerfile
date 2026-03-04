# ベースイメージは維持
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

# 開発・GUI用ユーザー作成
RUN useradd -m -u 1000 -s /bin/bash user

# Nav2（自律移動用）
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ros-humble-navigation2 \
      ros-humble-nav2-bringup \
    && rm -rf /var/lib/apt/lists/*

# rosdep 初期化
RUN rosdep init || true && rosdep update

# =========================================================
# ローカルソースコードの配置
# =========================================================
WORKDIR /opt
COPY . /opt/
RUN chown -R user:user /opt

# =========================================================
# 各コンポーネントのビルド
# =========================================================

# 1. YDLidar SDK（公式）のビルド
WORKDIR /opt/YDLidar-SDK
RUN mkdir -p build && cd build && \
    cmake .. && make -j$(nproc) && make install && \
    ldconfig

# 2. Roomba ワークスペースのビルド
WORKDIR /opt/roomba_ws
RUN /bin/bash -c "source /opt/ros/humble/setup.bash && \
    rosdep install --from-paths src --ignore-src -r -y && \
    colcon build --symlink-install"

# 3. YDLidar ROS2 ワークスペースのビルド
WORKDIR /opt/ydlidar_ws
RUN /bin/bash -c "source /opt/ros/humble/setup.bash && \
    rosdep install --from-paths src --ignore-src -r -y && \
    colcon build --symlink-install"

# =========================================================
# ルンバの通信速度設定を修正 (115200 baud を有効化)
# =========================================================
RUN sed -i 's/# baud: 115200/baud: 115200/' /opt/ros/humble/share/create_bringup/config/default.yaml

# 4. メインワークスペース (ros2_ws) のビルド
WORKDIR /opt/ros2_ws
RUN /bin/bash -c "source /opt/ros/humble/setup.bash && \
    source /opt/roomba_ws/install/setup.bash && \
    source /opt/ydlidar_ws/install/setup.bash && \
    rosdep install --from-paths src --ignore-src -r -y && \
    colcon build --symlink-install"

# =========================================================
# CAT UI 権限設定
# =========================================================
WORKDIR /opt/catui/CAT-UI-ROS2node
RUN chmod +x CAT-UI && \
    mkdir -p data/ipc && \
    chmod 1777 data/ipc

# =========================================================
# UI + ROS2 起動スクリプト (run-catui)
# =========================================================
RUN printf '%s\n' \
'#!/usr/bin/env bash' \
'set -eo pipefail' \
'echo "[INFO] run-catui started"' \
'source /opt/ros/humble/setup.bash' \
'source /opt/roomba_ws/install/setup.bash' \
'source /opt/ydlidar_ws/install/setup.bash' \
'source /opt/ros2_ws/install/setup.bash' \
'' \
'echo "[INFO] starting cat_robot_bringup"' \
'ros2 launch cat_robot_bringup system.launch.py &' \
'BRINGUP_PID=$!' \
'sleep 2' \
'' \
'cd /opt/catui/CAT-UI-ROS2node' \
'exec ./CAT-UI' \
> /usr/local/bin/run-catui && chmod +x /usr/local/bin/run-catui

WORKDIR /opt
CMD ["/usr/local/bin/run-catui"]