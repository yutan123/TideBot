import logging
import json
from typing import Optional, Any
from redis.asyncio import Redis, ConnectionPool
from redis.asyncio.retry import Retry
from redis.backoff import ExponentialBackoff
from redis.exceptions import ConnectionError, TimeoutError

logger = logging.getLogger("TideBot.Infrastructure.Cache")

class CacheEngine:
    """
    Redis 高性能异步缓存引擎
    用于存储热上下文状态、分布式锁、高频通道状态。具备指数退避熔断重试机制。
    """
    def __init__(self, redis_url: str = "redis://localhost:6379/0", max_connections: int = 50):
        # 配置内置高可用指数退避重试网络策略
        retry_strategy = Retry(ExponentialBackoff(cap=2.0, base=0.2), 3)
        
        self._pool = ConnectionPool.from_url(
            redis_url,
            max_connections=max_connections,
            decode_responses=True, # 自动完成文本级解码
            retry=retry_strategy,
            retry_on_timeout=True,
            retry_on_error=[ConnectionError, TimeoutError]
        )
        self.client: Redis = Redis(connection_pool=self._pool)
        logger.info("异步 Redis 缓存连接池加载完成。")

    async def get(self, key: str) -> Optional[str]:
        """提取热数据缓存字符串"""
        try:
            return await self.client.get(key)
        except Exception as e:
            logger.error(f"Redis 异常读取阻断, Key: {key}, 原因: {str(e)}")
            return None

    async def set(self, key: str, value: str, expire_seconds: Optional[int] = None) -> bool:
        """注入热缓存数据项"""
        try:
            return await self.client.set(key, value, ex=expire_seconds)
        except Exception as e:
            logger.error(f"Redis 异常持久化写阻断, Key: {key}, 原因: {str(e)}")
            return False

    async def get_json(self, key: str) -> Optional[Any]:
        """读取并自动反序列化 JSON 复合结构体"""
        data = await self.get(key)
        if not data:
            return None
        try:
            return json.loads(data)
        except json.JSONDecodeError:
            logger.error(f"Redis 缓存序列化破损毁坏损坏, Key: {key}")
            return None

    async def set_json(self, key: str, value: Any, expire_seconds: Optional[int] = None) -> bool:
        """自动序列化 JSON 结构体并注入热缓存"""
        try:
            serialized = json.dumps(value, ensure_ascii=False)
            return await self.set(key, serialized, expire_seconds)
        except Exception as e:
            logger.error(f"Redis JSON 序列化失败, Key: {key}, 原因: {str(e)}")
            return False

    async def delete(self, key: str) -> bool:
        """立刻从缓存中移除目标键"""
        try:
            affected = await self.client.delete(key)
            return affected > 0
        except Exception as e:
            logger.error(f"Redis 删除操作中断, Key: {key}, 原因: {str(e)}")
            return False

    async def close(self) -> None:
        """断开物理缓存池长连接"""
        await self._pool.disconnect()
        logger.info("Redis 异步长连接池已安全离线释放。")