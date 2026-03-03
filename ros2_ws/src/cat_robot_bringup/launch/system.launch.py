from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.conditions import IfCondition
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node
from launch_ros.actions import IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource
from ament_index_python.packages import get_package_share_directory
import os


def generate_launch_description():

    # --------------------------------------------------
    # Launch arguments
    # --------------------------------------------------
    use_ui = LaunchConfiguration('use_ui')
    use_roomba = LaunchConfiguration('use_roomba')
    use_lidar = LaunchConfiguration('use_lidar')
    use_localization = LaunchConfiguration('use_localization')
    use_nav2_controller = LaunchConfiguration('use_nav2_controller')

    nav2_params = LaunchConfiguration('nav2_params')

    return LaunchDescription([

        # =============================
        # Arguments
        # =============================
        DeclareLaunchArgument('use_ui', default_value='true'),
        DeclareLaunchArgument('use_roomba', default_value='true'),
        DeclareLaunchArgument('use_lidar', default_value='true'),
        DeclareLaunchArgument('use_localization', default_value='true'),
        DeclareLaunchArgument('use_nav2_controller', default_value='true'),

        DeclareLaunchArgument(
            'nav2_params',
            default_value='/opt/ros2_ws/src/cat_robot_bringup/config/nav2_controller_only.yaml',
            description='Nav2 controller-only parameter file'
        ),

        # ==========================================================
        # UI bridge (ROS2 -> UI IPC)
        # ==========================================================
        Node(
            package='catui_bridge',
            executable='catui_bridge',
            name='catui_bridge',
            output='screen',
            condition=IfCondition(use_ui),
            parameters=[{
                'ipc_root': '/opt/catui/CAT-UI-ROS2node/data/ipc/broadcast'
            }]
        ),

        # ==========================================================
        # Roomba driver (cmd_vel subscriber)
        # ==========================================================
        Node(
            package='create_driver',
            executable='create_driver',
            name='roomba_driver',
            output='screen',
            condition=IfCondition(use_roomba),
            parameters=[{
                'port': '/dev/roomba',
                'baud': 115200
            }]
        ),

        # ==========================================================
        # LiDAR driver (publish scan only)
        # ==========================================================
        Node(
            package='ydlidar_ros2',
            executable='ydlidar_node',
            name='ydlidar',
            output='screen',
            condition=IfCondition(use_lidar),
            parameters=[{
                'frame_id': 'laser_frame'
            }]
        ),

        # ==========================================================
        # Localization (NO map building)
        # slam_toolbox localization mode
        # ==========================================================
        Node(
            package='slam_toolbox',
            executable='localization_slam_toolbox_node',
            name='localization',
            output='screen',
            condition=IfCondition(use_localization),
            parameters=[{
                'use_sim_time': False
            }]
        ),

        # ==========================================================
        # Nav2 Controller ONLY (local costmap + controller)
        # ==========================================================
        IncludeLaunchDescription(
            PythonLaunchDescriptionSource(
                os.path.join(
                    get_package_share_directory('nav2_bringup'),
                    'launch',
                    'navigation_launch.py'
                )
            ),
            condition=IfCondition(use_nav2_controller),
            launch_arguments={
                'use_sim_time': 'false',
                'autostart': 'true',
                'params_file': nav2_params,
                # ★ map / planner / BT は params で無効化
            }.items()
        ),
    ])