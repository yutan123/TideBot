from typing import List, Optional
from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, Field

from api.dependencies import get_current_user, CurrentUserDomain

router = APIRouter(prefix="/bots", tags=["机器人核心实体与预设管理"])

class BotConfigurationSchema(BaseModel):
    id: Optional[str] = Field(None, description="Bot 唯一主键")
    name: str = Field(..., description="机器人可自定义名称")
    personality_prompt: str = Field(..., description="核心人格设定、说话规则 Prompt")
    style_preset: str = Field(..., description="开场预设及语境格式设定")
    max_context_tokens: int = Field(2048, description="硬截断滑动窗口最大 Token 上限")
    provider_id: str = Field(..., description="绑定大模型提供商的适配器标识")

@router.post("", status_code=status.HTTP_201_CREATED, response_model=BotConfigurationSchema)
async def create_bot_profile(
    payload: BotConfigurationSchema,
    current_user: CurrentUserDomain = Depends(get_current_user)
):
    """
    创建/注册全新机器人实体 (包括名称、人格设定、硬截断最大上下文上限)
    """
    # 此处接收前端 SaaS 控制台的数据包，后续直接透传到持久化层储存
    payload.id = "bot_entity_v1_99"
    return payload

@router.get("", response_model=List[BotConfigurationSchema])
async def list_registered_bots(current_user: CurrentUserDomain = Depends(get_current_user)):
    """
    获取当前系统底座内所有处于激活状态的 Bot 列表
    """
    return [
        BotConfigurationSchema(
            id="bot_entity_v1_01",
            name="潮汐学术助理",
            personality_prompt="你是一个不苟言笑的高级计算机专家，说话严谨简练。",
            style_preset="请用 Markdown 的代码块及表格标准输出结构",
            max_context_tokens=4096,
            provider_id="bailian_qwen_max"
        )
    ]

@router.patch("/{bot_id}", response_model=BotConfigurationSchema)
async def update_bot_personality(
    bot_id: str,
    payload: BotConfigurationSchema,
    current_user: CurrentUserDomain = Depends(get_current_user)
):
    """
    热修改 Bot 的运行时配置（如动态调整上下文、覆盖 Prompt 预设）
    """
    payload.id = bot_id
    return payload