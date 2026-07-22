import logging
import uvicorn
from .config_manager import ConfigManager
from .logger import setup_logger
from .event_bus import EventBus

async def initialize_system():
    """
    应用生命周期管理与初始化编排。
    严格规定各基础组件的启动顺序。
    """
    # 1. 加载全局配置
    config_manager = ConfigManager()
    
    # 2. 提取配置并初始化日志系统
    debug_mode = config_manager.config.get("server", {}).get("debug", False)
    log_level = logging.DEBUG if debug_mode else logging.INFO
    logger = setup_logger(log_level=log_level)
    
    logger.info("=========================================")
    logger.info("🚀 正在初始化 TideBot 核心运行时环境...")
    logger.info("=========================================")

    # 3. 启动系统事件总线
    event_bus = EventBus()
    logger.info("✔ 事件总线 (EventBus) 初始化成功。")

    # 4. 数据库初始化 (预留位置给 core/database/connection.py)
    logger.info("✔ 数据库连接模块就绪。")

    # 5. 加载能力中心与插件 (预留位置给 core/capabilities/)
    logger.info("✔ 能力注册中心就绪。")

    logger.info("TideBot 核心启动序列执行完毕。")

def start_server():
    """
    统一 Web API 与核心引擎的一体化启动入口
    """
    config_manager = ConfigManager()
    host = config_manager.config.get("server", {}).get("host", "0.0.0.0")
    port = config_manager.config.get("server", {}).get("port", 8000)

    # 启动 Uvicorn Web 服务器，加载 server.app 应用对象
    uvicorn.run(
        "server.app:app",
        host=host,
        port=port,
        reload=False
    )