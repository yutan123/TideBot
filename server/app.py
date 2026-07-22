from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from core.config_manager import ConfigManager
import logging

# 导入路由模块
from server.route_web import router as web_router
from server.route_app import router as app_router

# 初始化全局日志记录器
logger = logging.getLogger("TideBot")

@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    FastAPI 生命周期管理函数
    启动 FastAPI 服务时自动触发 TideBot 核心引擎初始化
    """
    logger.info("🌊 FastAPI 正在启动，开始初始化 TideBot 核心服务...")
    
    # 核心服务初始化逻辑挂载在此处
    from core.bootstrap import initialize_system
    await initialize_system()
    
    logger.info("🚀 TideBot API 及核心引擎已成功启动，准备接收请求！")
    yield
    logger.info("🛑 FastAPI 正在关闭，清理资源...")

def create_app() -> FastAPI:
    """工厂模式创建并组装 FastAPI 实例"""
    config = ConfigManager()
    
    app = FastAPI(
        title="TideBot Core Engine API",
        version="0.1.0",
        description="A production-grade AI Agent platform.",
        lifespan=lifespan
    )

    # 配置 CORS 中间件，允许跨域访问
    cors_origins = config.config.get("server", {}).get("cors_origins", ["*"])
    app.add_middleware(
        CORSMiddleware,
        allow_origins=cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # ---------------- 新增：处理根路径和图标请求 ----------------
    
    @app.get("/", tags=["System"])
    async def root_path():
        """根路径路由，友好的系统运行状态提示"""
        return {
            "message": "欢迎来到 TideBot API！核心引擎正在运行中 🌊",
            "docs_url": "/docs",
            "tip": "请访问 http://127.0.0.1:8000/docs 查看完整的 Swagger API 文档"
        }

    @app.get("/favicon.ico", include_in_schema=False)
    async def favicon():
        """静默处理浏览器自动请求的 favicon 图标，避免后台报 404 警告"""
        return {}
        
    # ----------------------------------------------------------

    # 注册路由组
    app.include_router(web_router)
    app.include_router(app_router)

    return app

# 暴露给 Uvicorn 运行的全局 app 对象
app = create_app()