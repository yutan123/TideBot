from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from core.config_manager import ConfigManager
from typing import Dict, List, Optional, Any, Union
import logging

# 导入路由
from server.route_web import router as web_router
from server.route_app import router as app_router

logger = logging.getLogger("TideBot")

@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    FastAPI 生命周期管理
    在服务启动前和关闭后执行系统级资源的准备和销毁
    """
    logger.info("FastAPI 准备接收 HTTP 请求...")
    # 这里可以安排启动定时任务 TaskManager().start() 等
    yield
    logger.info("FastAPI 正在关闭，清理 HTTP 资源...")
    # 这里可以安排关闭数据库连接等

def create_app() -> FastAPI:
    """工厂模式创建并组装 FastAPI 实例"""
    config = ConfigManager()
    
    app = FastAPI(
        title="TideBot Core Engine API",
        version="0.1.0",
        description="A production-grade AI Agent platform.",
        lifespan=lifespan
    )

    # 配置 CORS 中间件，允许前端或 App 跨域访问
    cors_origins = config.config.get("server", {}).get("cors_origins", ["*"])
    app.add_middleware(
        CORSMiddleware,
        allow_origins=cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # 注册路由组
    app.include_router(web_router)
    app.include_router(app_router)

    return app

# 提供给 Uvicorn 运行的全局 app 对象
app = create_app()
