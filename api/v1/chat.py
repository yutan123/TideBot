import asyncio
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from typing import List, Optional

from api.dependencies import get_current_user, CurrentUserDomain

router = APIRouter(prefix="/chat", tags=["高并发多模态流式对话核心"])

class MessageBody(BaseModel):
    role: str = Field(..., description="角色：user / assistant / system")
    content: str = Field(..., description="纯文本或序列化多模态资源定位")

class ChatStreamingRequest(BaseModel):
    bot_id: str = Field(..., description="目标驱动的机器人实例主键")
    messages: List[MessageBody] = Field(..., description="本次会话追加的上下文队列")
    image_bytes_base64: Optional[str] = Field(None, description="用于多模态识图的多媒体流切片")

async def dummy_llm_stream_generator(prompt: str):
    """
    模拟底座大模型适配网关的多模态异步迭代器
    用于保证 chat.py 的流式上行在没有 core 运行时的情况下即可安全拉起与渲染测试
    """
    response_mock = f"【TideBot 网关层非阻塞回传】已收到您的多模态输入。底座已自动激活无脑截断式上下文滑动窗口，正在流式透传。您的输入长度为: {len(prompt)}c。"
    for chunk in response_mock.split():
        yield f"data: {chunk}\n\n"
        await asyncio.sleep(0.08)

@router.post("/stream")
async def execute_low_latency_streaming(
    payload: ChatStreamingRequest,
    current_user: CurrentUserDomain = Depends(get_current_user)
):
    """
    端到端极致低延迟流式交互核心 API（支持管理端、多 IM、Android App 实时渲染）
    """
    if not payload.messages:
        raise HTTPException(status_code=400, detail="请求会话上下文中不可包含空消息主体")
        
    last_user_input = payload.messages[-1].content
    
    # 保持底层协议的纯净性，返回标准的 Server-Sent Events (SSE) 流
    return StreamingResponse(
        dummy_llm_stream_generator(last_user_input),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"  # 禁用 Nginx 缓存，确保流式打字机效果立刻输出
        }
    )