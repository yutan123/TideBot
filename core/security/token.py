import jwt
from datetime import datetime, timedelta, timezone
from core.config_manager import ConfigManager
from typing import Dict, Any, Optional

class TokenManager:
    """JWT 令牌管理器，负责生成和解析 Token"""
    
    @staticmethod
    def create_access_token(data: Dict[str, Any], expires_delta: Optional[timedelta] = None) -> str:
        config = ConfigManager().env
        to_encode = data.copy()
        
        if expires_delta:
            expire = datetime.now(timezone.utc) + expires_delta
        else:
            expire = datetime.now(timezone.utc) + timedelta(days=config.jwt_expiration_days)
            
        to_encode.update({"exp": expire})
        # 使用 HS256 算法和配置文件中的安全密钥进行签名
        encoded_jwt = jwt.encode(to_encode, config.app_secret_key, algorithm="HS256")
        return encoded_jwt

    @staticmethod
    def decode_token(token: str) -> Optional[Dict[str, Any]]:
        config = ConfigManager().env
        try:
            payload = jwt.decode(token, config.app_secret_key, algorithms=["HS256"])
            return payload
        except jwt.ExpiredSignatureError:
            # 令牌过期
            return None
        except jwt.InvalidTokenError:
            # 令牌无效
            return None