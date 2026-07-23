<template>
  <div class="chat-container">
    <!-- 聊天信息展示区 -->
    <div class="chat-messages">
      <!-- 机器人消息 -->
      <div class="message bot">
        <div class="avatar">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <rect x="3" y="11" width="18" height="10" rx="2"></rect>
            <circle cx="12" cy="5" r="2"></circle>
            <path d="M12 7v4"></path>
            <line x1="8" y1="16" x2="8" y2="16"></line>
            <line x1="16" y1="16" x2="16" y2="16"></line>
          </svg>
        </div>
        <div class="bubble">
          你好！我是 TideBot，我已经准备好为你服务了。今天想聊点什么？
        </div>
      </div>

      <!-- 用户消息 -->
      <div class="message user">
        <div class="bubble">
          帮我测试一下现在的毛玻璃和圆角质感怎么样？
        </div>
      </div>
    </div>

    <!-- 底部输入悬浮舱 (Telegram风) -->
    <div class="chat-input-wrapper">
      <div class="chat-input-box glass-panel">
        <button class="icon-btn btn-spring attach-btn">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48"></path>
          </svg>
        </button>
        <input type="text" placeholder="给 TideBot 发送消息..." class="message-input" />
        <button class="icon-btn btn-spring send-btn">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <line x1="22" y1="2" x2="11" y2="13"></line>
            <polygon points="22 2 15 22 11 13 2 9 22 2"></polygon>
          </svg>
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.chat-container {
  display: flex;
  flex-direction: column;
  height: 100%;
  position: relative;
}

.chat-messages {
  flex: 1;
  overflow-y: auto;
  padding: 24px;
  display: flex;
  flex-direction: column;
  gap: 20px;
  padding-bottom: 100px; /* 为底部输入框留出空间 */
}

.message {
  display: flex;
  align-items: flex-end;
  gap: 12px;
  max-width: 85%;
}

.message.bot {
  align-self: flex-start;
}

.message.user {
  align-self: flex-end;
  flex-direction: row-reverse;
}

.avatar {
  width: 36px;
  height: 36px;
  background: var(--glass-bg);
  border: 1px solid var(--glass-border);
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 4px 12px rgba(0,0,0,0.05);
  flex-shrink: 0;
}

.bubble {
  padding: 14px 18px;
  border-radius: 20px;
  font-size: 15px;
  line-height: 1.5;
  box-shadow: 0 2px 8px rgba(0,0,0,0.04);
}

.bot .bubble {
  background: var(--glass-bg);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
  border: 1px solid var(--glass-border);
  border-bottom-left-radius: 4px;
}

.user .bubble {
  background: var(--primary);
  color: #fff;
  border-bottom-right-radius: 4px;
  box-shadow: 0 4px 16px rgba(0, 122, 255, 0.25);
}

/* 底部输入框毛玻璃 */
.chat-input-wrapper {
  position: absolute;
  bottom: 0;
  left: 0;
  right: 0;
  padding: 0 24px 24px;
  background: linear-gradient(to top, var(--bg-base) 60%, transparent);
}

.chat-input-box {
  display: flex;
  align-items: center;
  gap: 12px;
  background: var(--glass-bg);
  backdrop-filter: blur(24px) saturate(180%);
  -webkit-backdrop-filter: blur(24px) saturate(180%);
  border: 1px solid var(--glass-border);
  border-radius: var(--radius-pill);
  padding: 8px 12px;
  box-shadow: var(--glass-shadow);
}

.message-input {
  flex: 1;
  background: transparent;
  border: none;
  outline: none;
  color: var(--text-main);
  font-size: 15px;
  padding: 8px 4px;
}

.message-input::placeholder {
  color: var(--text-secondary);
}

.icon-btn {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-secondary);
}

.send-btn {
  background: var(--primary);
  color: #fff;
}
</style>