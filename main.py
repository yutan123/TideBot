import sys
import logging
from core.bootstrap import start_server

def start():
    """TideBot 统一一键启动入口"""
    print("🌊 正在启动 TideBot AI Agent 全栈引擎...")
    try:
        # 直接启动内置 Web 服务与核心引擎
        start_server()
    except KeyboardInterrupt:
        print("\n[TideBot] 收到退出信号 (Ctrl+C)，正在安全关闭服务...")
        sys.exit(0)
    except Exception as e:
        logging.error(f"[TideBot] 启动失败，发生致命错误: {e}", exc_info=True)
        sys.exit(1)

if __name__ == "__main__":
    start()