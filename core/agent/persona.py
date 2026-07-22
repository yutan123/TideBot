# 导入 typing 模块中的 Dict 类型，解决 NameError 报错
from typing import Dict
from core.config_manager import ConfigManager

class PersonaBuilder:
    """管理系统级提示词和 Agent 的人设"""
    
    @staticmethod
    def build_system_prompt() -> Dict[str, str]:
        """构建系统级 System Prompt"""
        config = ConfigManager().config
        template = config.get("agent", {}).get(
            "system_prompt_template", 
            "你是一个名为 TideBot 的智能助理。"
        )
        
        # 这里可以加入更多的动态参数替换，例如当前日期、系统状态等
        final_prompt = f"{template}\n请遵循最佳安全规范，严谨地使用工具完成用户意图。"
        
        return {
            "role": "system",
            "content": final_prompt
        }