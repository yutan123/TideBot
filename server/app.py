from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from contextlib import asynccontextmanager
from core.config_manager import ConfigManager
import logging
import os

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

    # 注册 Backend API 路由组
    app.include_router(web_router)
    app.include_router(app_router)

    # ---------------- 挂载前端控制台 UI 静态资源 ----------------
    # 获取 web_ui 文件夹的绝对路径
    web_ui_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "web_ui")

    if os.path.exists(web_ui_path):
        # 1. 挂载静态资源（如 CSS, JS 文件），访问路径映射为 /static/...
        app.mount("/static", StaticFiles(directory=web_ui_path), name="static")

        # 2. 根路径直接返回 index.html 页面
        @app.get("/", tags=["Frontend Console"])
        async def render_web_console():
            index_file = os.path.join(web_ui_path, "index.html")
            if os.path.exists(index_file):
                return FileResponse(index_file)
            return {"error": "index.html 未在 web_ui 目录中找到"}
    else:
        logger.warning(f"⚠️ 未找到前端目录: {web_ui_path}，控制台页面将无法访问。")

    @app.get("/favicon.ico", include_in_schema=False)
    async def favicon():
        """静默处理浏览器自动请求的 favicon 图标"""
        return {}

    return app

# 暴露给 Uvicorn 运行的全局 app 对象
app = create_app()