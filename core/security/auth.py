from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from core.security.token import TokenManager
from core.security.permissions import Role

# 声明 OAuth2 机制，让 FastAPI 知道从哪里获取 Token
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="api/v1/auth/login")

async def get_current_user(token: str = Depends(oauth2_scheme)) -> dict:
    """
    FastAPI 依赖注入函数：验证请求头中的 JWT 令牌并返回用户信息
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="无法验证您的身份凭证",
        headers={"WWW-Authenticate": "Bearer"},
    )
    
    payload = TokenManager.decode_token(token)
    if payload is None:
        raise credentials_exception
        
    user_id: str = payload.get("sub")
    role: str = payload.get("role", Role.GUEST)
    
    if user_id is None:
        raise credentials_exception
        
    return {"user_id": user_id, "role": role}

async def require_admin(current_user: dict = Depends(get_current_user)):
    """依赖注入函数：强制要求管理员权限"""
    if current_user.get("role") != Role.ADMIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="您没有权限执行此操作"
        )
    return current_user