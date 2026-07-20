from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from jose import jwt
from passlib.context import CryptContext
from pydantic import BaseModel

from env import settings

router = APIRouter(prefix="/auth", tags=["安全身份认证中心"])

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

class TokenResponse(BaseModel):
    access_token: str
    token_type: str
    expires_in_minutes: int

class UserRegisterInput(BaseModel):
    username: str
    password: str

def generate_jwt_token(data: dict, expires_delta: timedelta) -> str:
    """内部工具方法：构造高强度 JWT"""
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + expires_delta
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)

@router.post("/register", status_code=status.HTTP_201_CREATED)
async def register_account(payload: UserRegisterInput):
    """
    控制台系统管理员/用户注册接口
    """
    # 模拟持久化边界处理 (后续切入 models/orm 存储)
    hashed_password = pwd_context.hash(payload.password)
    return {
        "status": "success",
        "message": "用户节点初始化注册成功",
        "detail": {"username": payload.username, "fingerprint": hashed_password[:15]}
    }

@router.post("/login", response_model=TokenResponse)
async def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends()):
    """
    SaaS 级多端鉴权核心入口，签发高安全性 Bearer 令牌
    """
    # 临时模拟鉴权认证流程 (后续替换为核心 ORM 数据库校验)
    if form_data.username != "admin":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="当前用户账号在底座系统内不存在或被拒绝访问"
        )
        
    # 模拟静态密码鉴权通过
    mock_user_id = "usr_tidebot_778899"
    token_data = {
        "sub": mock_user_id,
        "username": form_data.username,
        "role": "admin"
    }
    
    expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    token = generate_jwt_token(data=token_data, expires_delta=expires)
    
    return TokenResponse(
        access_token=token,
        token_type="bearer",
        expires_in_minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES
    )