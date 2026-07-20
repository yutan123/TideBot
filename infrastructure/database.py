import logging
import asyncio
from typing import AsyncGenerator
from contextlib import asynccontextmanager
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base

logger = logging.getLogger("TideBot.Infrastructure.Database")
Base = declarative_base()

class DatabaseEngine:
    """
    企业级高性能异步数据库引擎
    管理连接池生命周期、事务控制，并提供无感知自动回滚机制。
    """
    def __init__(self, db_url: str = "sqlite+aiosqlite:///./tidebot.db", pool_size: int = 20, max_overflow: int = 10):
        # 生产环境推荐换用：postgresql+asyncpg://user:pass@host/dbname
        is_sqlite = db_url.startswith("sqlite")
        
        connect_args = {"check_same_thread": False} if is_sqlite else {}
        
        engine_kwargs = {
            "echo": False,
            "future": True
        }
        
        if not is_sqlite:
            engine_kwargs.update({
                "pool_size": pool_size,
                "max_overflow": max_overflow,
                "pool_recycle": 1800,
                "pool_pre_ping": True
            })

        self._engine = create_async_engine(db_url, connect_args=connect_args, **engine_kwargs)
        self._session_factory = async_sessionmaker(
            bind=self._engine, 
            class_=AsyncSession, 
            expire_on_commit=False
        )
        logger.info("异步数据库引擎连接池初始化完成。")

    async def create_all_tables(self) -> None:
        """初始化 DDL 建表脚本（生产环境推荐配合 Alembic 使用）"""
        async with self._engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
        logger.info("数据库实体 schema 自动建表检查完成。")

    @asynccontextmanager
    def session(self) -> AsyncGenerator[AsyncSession, None]:
        """
        高可用异步上下关系事务上下文管理器
        发生任何未捕获异常时自动安全 Rollback，正常结束时自动 Commit 并回收连接。
        """
        session: AsyncSession = self._session_factory()
        try:
            yield session
            await session.commit()
        except Exception as e:
            await session.rollback()
            logger.error(f"数据库会话拦截到未捕获崩溃，已强制回滚事务。详情: {str(e)}")
            raise e
        finally:
            await session.close()

    async def close(self) -> None:
        """优雅关闭数据库物理连接池"""
        if self._engine:
            await self._engine.dispose()
            logger.info("数据库物理连接池已安全释放销毁。")