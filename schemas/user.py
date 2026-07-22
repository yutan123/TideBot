# 移除了未使用的 EmailStr 导入，使代码更精简
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime

class UserCreate(BaseModel):
    """
    用户注册时的请求模型
    用于校验前端提交的注册数据是否合法
    """
    username: str = Field(..., min_length=3, max_length=50, description="用户名，需唯一")
    password: str = Field(..., min_length=6, description="明文密码，服务器会将其加密存储")

class UserLogin(BaseModel):
    """
    用户登录时的请求模型
    用于校验登录时提交的凭证
    """
    username: str
    password: str

class UserInfo(BaseModel):
    """
    脱敏后的用户信息响应模型
    作为返回值发给前端，严格控制不包含密码等敏感字段
    """
    id: str
    username: str
    role: str
    is_active: bool
    created_at: datetime
    
    class Config:
        """
        Pydantic 配置类
        允许直接将 SQLAlchemy ORM 查询出的数据库对象转换为此 Pydantic 模型
        """
        from_attributes = True