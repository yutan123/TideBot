from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from core.config_manager import ConfigManager
import logging

# 移除了此处未使用的 typing 导入 (Dict, List, 等)，保持命名空间干净
# 导入路由模块
from server.route_web import router as web_router
from server.route_app import router as app_router

# 初始化全局日志记录器
logger = logging.getLogger("TideBot")

@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    FastAPI 生命周期管理函数
    - yield 之前的代码会在服务启动时执行（如：建立数据库连接、加载模型）
    - yield 之后的代码会在服务关闭时执行（如：释放资源、保存状态）
    """
    logger.info("🌊 FastAPI 准备接收 HTTP 请求...")
    # TODO: 这里可以安排启动定时任务 TaskManager().start() 等初始化操作
    
    yield  # 此时应用正在运行并处理请求
    
    logger.info("🛑 FastAPI 正在关闭，清理 HTTP 资源...")
    # TODO: 这里可以安排关闭数据库连接等清理操作

def create_app() -> FastAPI:
    """
    工厂模式创建并组装 FastAPI 实例
    这种设计模式便于未来编写单元测试或创建多个不同的应用实例
    """
    # 实例化配置管理器
    config = ConfigManager()
    
    # 初始化 FastAPI 应用并绑定生命周期
    app = FastAPI(
        title="TideBot Core Engine API",
        version="0.1.0",
        description="A production-grade AI Agent platform.",
        lifespan=lifespan
    )

    # 跨域资源共享 (CORS) 配置
    # 允许前端浏览器或跨域的 App 客户端安全地调用 API
    cors_origins = config.config.get("server", {}).get("cors_origins", ["*"])
    app.add_middleware(
        CORSMiddleware,
        allow_origins=cors_origins,
        allow_credentials=True,
        allow_methods=["*"],  # 允许所有 HTTP 方法 (GET, POST, OPTIONS 等)
        allow_headers=["*"],  # 允许所有 HTTP 请求头
    )

    # 挂载/注册路由组
    # 将拆分在不同文件中的路由统一整合到 app 实例中
    app.include_router(web_router)
    app.include_router(app_router)

    return app

# 暴露给 Uvicorn 运行的全局 app 对象
# 当执行 `uvicorn server.app:app` 时，寻找的就是这个变量
app = create_app()