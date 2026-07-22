import bcrypt

class PasswordHasher:
    """提供通用的密码加密与验证工具"""
    
    @staticmethod
    def hash_password(plain_password: str) -> str:
        """将明文密码转换为 bcrypt 密文"""
        # 生成盐并哈希，存入数据库的应该是 decode 后的字符串
        salt = bcrypt.gensalt()
        hashed_bytes = bcrypt.hashpw(plain_password.encode('utf-8'), salt)
        return hashed_bytes.decode('utf-8')

    @staticmethod
    def verify_password(plain_password: str, hashed_password: str) -> bool:
        """验证明文密码是否与密文匹配"""
        try:
            return bcrypt.checkpw(
                plain_password.encode('utf-8'),
                hashed_password.encode('utf-8')
            )
        except Exception:
            return False