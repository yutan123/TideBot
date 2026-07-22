from pydantic import BaseModel, Field
# 显式导入所有需要的类型提示，确保不会出现 NameError
from typing import List, Optional, Dict, Any

class ChatMessage(BaseModel):
    """
    单条聊天消息的校验模型
    用于规范前端传来的每一条对话记录的格式
    """
    role: str = Field(..., description="消息发送者角色 (必须是 user, assistant 或 system)")
    content: str = Field(..., description="消息的具体文本内容")

class ChatRequest(BaseModel):
    """
    用户发起聊天请求的参数模型
    定义了 App 端请求后端 /chat 接口时必须携带的数据体
    """
    session_id: str = Field(..., description="当前会话的唯一标识，用于追踪多轮对话")
    query: str = Field(..., description="用户当前输入的问题或指令")
    
    # 使用 List 指定这是一个列表，内部元素必须是 ChatMessage 模型
    history: Optional[List[ChatMessage]] = Field(
        default_factory=list, 
        description="前端传入的最近历史记录，用于补充上下文"
    )
    
    model_override: Optional[str] = Field(
        None, 
        description="如果用户指定了特定模型，则覆盖系统默认配置"
    )

class ChatResponse(BaseModel):
    """
    API 返回给客户端的聊天响应模型
    规范后端返回给前端的数据结构
    """
    session_id: str
    reply: str = Field(..., description="TideBot 的最终文本回复")
    
    # 这里的 Dict 必须从 typing 中导入，表示一个键是字符串、值是整数的字典
    usage: Optional[Dict[str, int]] = Field(
        None, 
        description="Token 消耗统计 (例如 {'prompt_tokens': 10, 'completion_tokens': 20})"
    )
    
    processing_time_ms: Optional[int] = Field(
        None, 
        description="服务器处理耗时 (毫秒)"
    )