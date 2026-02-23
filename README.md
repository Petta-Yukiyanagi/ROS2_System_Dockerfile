# Cat IoT Robot UI (ROS2 + Docker)

## Overview
This repository provides a Docker-based ROS2 (Humble) environment for:
- Roomba 600 series control
- Nav2 navigation stack
- YDLidar
- Java/Processing-based CAT UI

## Requirements
- Docker
- USB connection to Roomba (ttyUSB)
- X11 environment (RealVNC supported)

## Build
```bash
docker build -t catui:latest .