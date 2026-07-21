from enum import Enum

class Role(str, Enum):
    """系统角色定义"""
    ADMIN = "admin"       # 管理员，拥有所有权限
    USER = "user"         # 普通用户，只能访问自身数据
    GUEST = "guest"       # 访客，受限访问

class PermissionChecker:
    """权限校验器，用于验证用户是否拥有操作特定资源的权限"""
    
    @staticmethod
    def has_permission(user_role: str, required_role: str) -> bool:
        """
        简单的 RBAC 权限校验逻辑
        ADMIN 拥有所有权限，USER 拥有 USER 及 GUEST 权限
        """
        role_hierarchy = {
            Role.ADMIN: 3,
            Role.USER: 2,
            Role.GUEST: 1
        }
        
        user_level = role_hierarchy.get(user_role, 0)
        required_level = role_hierarchy.get(required_role, 999)
        
        return user_level >= required_level