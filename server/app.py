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

    # ⚠️ 必须先挂载 API 路由，以防被 Catch-All 拦截
    app.include_router(web_router)
    app.include_router(app_router)

    # ---------------- 核心修复：SPA 静态资源与路由挂载 ----------------
    
    current_dir = os.path.dirname(os.path.abspath(__file__))
    
    # 强制匹配带下划线的 web_ui
    if os.path.exists(os.path.join(current_dir, "web_ui")):
        web_ui_path = os.path.join(current_dir, "web_ui")
    else:
        web_ui_path = os.path.join(os.path.dirname(current_dir), "web_ui")

    assets_path = os.path.join(web_ui_path, "assets")

    # 1. 挂载 Vite 打包生成的 /assets 静态资源目录
    if os.path.exists(assets_path):
        app.mount("/assets", StaticFiles(directory=assets_path), name="assets")
        logger.info(f"✅ 成功挂载前端静态资源: {assets_path}")
    else:
        logger.error(f"❌ 静态目录不存在，跳过挂载: {assets_path} (请确认前端是否已执行 build)")

    # 2. 挂载前端的根目录零散静态文件 (如 vite.svg)
    @app.get("/vite.svg", include_in_schema=False)
    async def vite_svg():
        svg_file = os.path.join(web_ui_path, "vite.svg")
        if os.path.exists(svg_file):
            return FileResponse(svg_file)
        return JSONResponse(status_code=404, content={})

    @app.get("/favicon.ico", include_in_schema=False)
    async def favicon():
        favicon_file = os.path.join(web_ui_path, "favicon.ico")
        if os.path.exists(favicon_file):
            return FileResponse(favicon_file)
        return JSONResponse(status_code=404, content={})

    # 3. Catch-All 路由：Vue Router History 模式核心
    # 只要不是以上明确声明的后端 API 或静态文件，一律返回 index.html 扔给前端解析
    @app.get("/{catchall:path}", tags=["Frontend Console"])
    async def render_web_console(catchall: str):
        index_file = os.path.join(web_ui_path, "index.html")
        if os.path.exists(index_file):
            return FileResponse(index_file)
        
        # 依然找不到，说明开发者忘记打包了
        return JSONResponse(
            status_code=404, 
            content={"error": f"前端入口文件未找到，请在前端目录执行 npm run build。预期路径: {index_file}"}
        )

    return app

app = create_app()