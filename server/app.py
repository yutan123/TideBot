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
    # 读取配置，保留了你原有的逻辑
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

    # ---------------- 修复区：挂载前端控制台 UI 静态资源 ----------------
    
    # 获取当前 app.py 的绝对路径所在的目录
    current_dir = os.path.dirname(os.path.abspath(__file__))
    
    # 动态智能寻找 webui 目录 (统一使用你的结构名 webui，去掉下划线)
    # 兼容 app.py 在项目根目录 或 在 server/ 目录下的两种情况
    if os.path.exists(os.path.join(current_dir, "webui")):
        webui_path = os.path.join(current_dir, "webui")
    else:
        webui_path = os.path.join(os.path.dirname(current_dir), "webui")

    assets_path = os.path.join(webui_path, "assets")

    # 1. 挂载 /assets 静态资源路径
    if os.path.exists(assets_path):
        app.mount("/assets", StaticFiles(directory=assets_path), name="assets")
        logger.info(f"✅ 成功挂载静态资源目录: {assets_path}")
    else:
        logger.error(f"❌ 严重错误: 未找到静态资源目录 {assets_path}。请检查路径！")

    # 2. 根路径直接返回 index.html 页面
    @app.get("/", tags=["Frontend Console"])
    async def render_web_console():
        index_file = os.path.join(webui_path, "index.html")
        if os.path.exists(index_file):
            return FileResponse(index_file)
        return {"error": f"index.html 未找到，请检查 {webui_path} 目录。"}

    @app.get("/favicon.ico", include_in_schema=False)
    async def favicon():
        """静默处理浏览器自动请求的 favicon 图标"""
        return {}

    return app

# 暴露给 Uvicorn 运行的全局 app 对象
app = create_app()