from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
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
    logger.info("🌊 FastAPI 正在启动，开始初始化 TideBot 核心服务...")
    from core.bootstrap import initialize_system
    await initialize_system()
    logger.info("🚀 TideBot API 及核心引擎已成功启动，准备接收请求！")
    yield
    logger.info("🛑 FastAPI 正在关闭，清理资源...")

def create_app() -> FastAPI:
    config = ConfigManager()
    
    app = FastAPI(
        title="TideBot Core Engine API",
        version="0.1.0",
        lifespan=lifespan
    )

    cors_origins = config.config.get("server", {}).get("cors_origins", ["*"])
    app.add_middleware(
        CORSMiddleware,
        allow_origins=cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(web_router)
    app.include_router(app_router)

    # ---------------- 核心修复：静态资源挂载 ----------------
    
    current_dir = os.path.dirname(os.path.abspath(__file__))
    
    # 强制匹配带下划线的 web_ui
    if os.path.exists(os.path.join(current_dir, "web_ui")):
        web_ui_path = os.path.join(current_dir, "web_ui")
    else:
        web_ui_path = os.path.join(os.path.dirname(current_dir), "web_ui")

    assets_path = os.path.join(web_ui_path, "assets")

    # FastAPI 的 StaticFiles 如果目录不存在会直接抛出 RuntimeError 导致 500 错误
    # 这里增加严格的路径存在性校验
    if os.path.exists(assets_path):
        app.mount("/assets", StaticFiles(directory=assets_path), name="assets")
        logger.info(f"✅ 成功挂载前端静态资源: {assets_path}")
    else:
        logger.error(f"❌ 静态目录不存在，跳过挂载: {assets_path}")

    @app.get("/", tags=["Frontend Console"])
    async def render_web_console():
        index_file = os.path.join(web_ui_path, "index.html")
        if os.path.exists(index_file):
            return FileResponse(index_file)
        # 返回 404 状态码而不是触发 500 异常
        return JSONResponse(status_code=404, content={"error": f"前端入口文件未找到: {index_file}"})

    @app.get("/favicon.ico", include_in_schema=False)
    async def favicon():
        return {}

    return app

app = create_app()