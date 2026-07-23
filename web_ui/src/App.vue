<template>
  <div class="app-container" :class="{ 'dark': isDarkMode }">
    
    <!-- 全局顶部导航栏 (TopBar) - 采用毛玻璃悬浮设计 -->
    <header class="topbar">
      <!-- 左侧：菜单按钮 + 动态标题 -->
      <div class="topbar-left">
        <button class="icon-btn btn-spring hamburger" @click="toggleSidebar">
          <!-- 原生 SVG 三条杠，圆润线条 -->
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round">
            <line x1="3" y1="12" x2="21" y2="12"></line>
            <line x1="3" y1="6" x2="21" y2="6"></line>
            <line x1="3" y1="18" x2="21" y2="18"></line>
          </svg>
        </button>
        
        <div class="brand-title">
          <span>TideBot</span>
          <!-- 根据模式动态切换的极简副标题 -->
          <span class="brand-subtitle" :class="{ 'is-chat': isChatMode }">
            {{ isChatMode ? 'chat' : '控制台' }}
          </span>
        </div>
      </div>

      <!-- 右侧：全局控制区 -->
      <div class="topbar-right">
        
        <!-- 连接APP 按钮 -->
        <button class="app-connect-btn btn-spring">
          连接 APP
        </button>

        <!-- 日/夜间模式无缝切换 (SVG 太阳/月亮) -->
        <button class="icon-btn btn-spring theme-toggle" @click="toggleTheme">
          <svg v-if="!isDarkMode" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="12" cy="12" r="5"></circle>
            <line x1="12" y1="1" x2="12" y2="3"></line>
            <line x1="12" y1="21" x2="12" y2="23"></line>
            <line x1="4.22" y1="4.22" x2="5.64" y2="5.64"></line>
            <line x1="18.36" y1="18.36" x2="19.78" y2="19.78"></line>
            <line x1="1" y1="12" x2="3" y2="12"></line>
            <line x1="21" y1="12" x2="23" y2="12"></line>
            <line x1="4.22" y1="19.78" x2="5.64" y2="18.36"></line>
            <line x1="18.36" y1="5.64" x2="19.78" y2="4.22"></line>
          </svg>
          <svg v-else width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"></path>
          </svg>
        </button>

        <!-- 模式切换：iOS 风的椭圆滑动开关 -->
        <div class="mode-switch-wrapper" @click="isChatMode = !isChatMode">
          <div class="mode-switch" :class="{ 'active': isChatMode }">
            <div class="switch-knob">
              {{ isChatMode ? 'chat' : '控制台' }}
            </div>
          </div>
        </div>

      </div>
    </header>

    <!-- 侧边栏遮罩层 (移动端) -->
    <div class="sidebar-overlay" :class="{ 'show': isSidebarOpen }" @click="toggleSidebar"></div>

    <!-- 侧边栏 (Sidebar) - 后续会抽离成独立组件 -->
    <aside class="sidebar" :class="{ 'open': isSidebarOpen }">
      <div class="sidebar-content">
        <!-- 占位菜单项，排版已经预留足够的呼吸感 -->
        <div class="menu-item active">数据大盘</div>
        <div class="menu-item">普通设置</div>
        <div class="menu-item">高级设置</div>
        <div class="menu-item">模型提供商</div>
      </div>
    </aside>

    <!-- 核心内容区 (动态路由出口位置) -->
    <main class="main-content">
      <div class="placeholder-content">
        <!-- 临时占位，展示毛玻璃卡片效果 -->
        <div class="glass-card">
          <h2>当前模式: {{ isChatMode ? 'Chat 模式' : '控制台模式' }}</h2>
          <p>主内容区已完美留白，侧边栏在手机端可滑动呼出，顶部栏支持多态联动。</p>
        </div>
      </div>
    </main>

  </div>
</template>

<script setup>
import { ref, watch } from 'vue'

// 状态控制
const isDarkMode = ref(false)
const isChatMode = ref(false)
const isSidebarOpen = ref(false)

// 切换主题
const toggleTheme = () => {
  isDarkMode.value = !isDarkMode.value
  if (isDarkMode.value) {
    document.documentElement.classList.add('dark')
  } else {
    document.documentElement.classList.remove('dark')
  }
}

// 切换侧边栏
const toggleSidebar = () => {
  isSidebarOpen.value = !isSidebarOpen.value
}
</script>

<style scoped>
.app-container {
  display: flex;
  flex-direction: column;
  height: 100vh;
  width: 100vw;
  position: relative;
}

/* ================= 顶部导航栏 (TopBar) ================= */
.topbar {
  position: absolute;
  top: 16px;
  left: 16px;
  right: 16px;
  height: 60px;
  background: var(--glass-bg);
  backdrop-filter: blur(24px) saturate(180%);
  -webkit-backdrop-filter: blur(24px) saturate(180%);
  border: 1px solid var(--glass-border);
  border-radius: var(--radius-pill); /* 极致 iOS 圆润感 */
  box-shadow: var(--glass-shadow);
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 16px 0 20px;
  z-index: 100;
}

.topbar-left, .topbar-right {
  display: flex;
  align-items: center;
  gap: 16px;
}

/* 左侧标题 */
.brand-title {
  font-size: 20px;
  font-weight: 700;
  display: flex;
  align-items: baseline;
  gap: 6px;
  letter-spacing: -0.5px;
}

.brand-subtitle {
  font-size: 13px;
  font-weight: 500;
  opacity: 0.6;
  transition: all 0.3s var(--spring);
}
.brand-subtitle.is-chat {
  font-size: 14px;
  color: var(--primary);
  opacity: 1;
}

/* 按钮基础 */
.icon-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-main);
  opacity: 0.8;
}

/* 连接 APP 按钮 */
.app-connect-btn {
  background: var(--primary);
  color: #fff;
  padding: 8px 16px;
  border-radius: var(--radius-pill);
  font-size: 14px;
  font-weight: 600;
  letter-spacing: 0.5px;
  box-shadow: 0 4px 12px rgba(0, 122, 255, 0.3);
}

/* ================= 滑动开关 (Mode Switch) iOS 风 ================= */
.mode-switch-wrapper {
  cursor: pointer;
  display: flex;
  align-items: center;
}

.mode-switch {
  position: relative;
  width: 76px;
  height: 36px;
  background-color: var(--switch-bg);
  border-radius: var(--radius-pill);
  transition: background-color 0.3s var(--ease-out);
  padding: 3px;
  box-shadow: inset 0 1px 3px rgba(0,0,0,0.1);
}

.mode-switch.active {
  background-color: var(--primary);
}

.switch-knob {
  position: absolute;
  top: 3px;
  left: 3px;
  width: 44px;
  height: 30px;
  background-color: #ffffff;
  border-radius: var(--radius-pill);
  box-shadow: 0 2px 8px rgba(0,0,0,0.15), 0 1px 2px rgba(0,0,0,0.1);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 12px;
  font-weight: 700;
  color: #1c1c1e;
  transition: transform 0.4s var(--spring);
}

.mode-switch.active .switch-knob {
  transform: translateX(26px);
  color: var(--primary);
}

/* ================= 侧边栏 (Sidebar) Telegram 风毛玻璃 ================= */
.sidebar {
  position: absolute;
  top: 92px; /* 避开顶部栏 */
  bottom: 16px;
  left: 16px;
  width: 240px;
  background: var(--glass-bg);
  backdrop-filter: blur(24px) saturate(180%);
  -webkit-backdrop-filter: blur(24px) saturate(180%);
  border: 1px solid var(--glass-border);
  border-radius: var(--radius-lg);
  box-shadow: var(--glass-shadow);
  z-index: 90;
  transform: translateX(0);
  transition: transform 0.4s var(--spring), opacity 0.3s ease;
  overflow: hidden;
}

.sidebar-content {
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 8px; /* 极简的留白间距 */
}

.menu-item {
  padding: 14px 16px;
  border-radius: var(--radius-md);
  font-size: 15px;
  font-weight: 500;
  color: var(--text-main);
  opacity: 0.7;
  cursor: pointer;
  transition: all 0.2s ease;
}

.menu-item:hover {
  background: rgba(120, 120, 120, 0.1);
  opacity: 1;
}

.menu-item.active {
  background: var(--primary);
  color: #fff;
  opacity: 1;
  box-shadow: 0 4px 12px rgba(0, 122, 255, 0.2);
}

/* 侧边栏遮罩 (仅移动端生效) */
.sidebar-overlay {
  display: none;
}

/* ================= 主内容区 ================= */
.main-content {
  position: absolute;
  top: 92px;
  bottom: 16px;
  left: 272px; /* 侧边栏宽度 240 + 16px 左边距 + 16px 间隙 */
  right: 16px;
  overflow-y: auto;
  border-radius: var(--radius-lg);
  transition: left 0.4s var(--spring);
}

/* 毛玻璃卡片基类 (复用) */
.glass-card {
  background: var(--glass-bg);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
  border: 1px solid var(--glass-border);
  border-radius: var(--radius-lg);
  padding: 32px;
  box-shadow: var(--glass-shadow);
  margin-bottom: 24px;
}

.glass-card h2 {
  margin-bottom: 12px;
  font-weight: 600;
}

.glass-card p {
  color: var(--text-secondary);
  line-height: 1.6;
}

/* ================= 移动端适配 (Media Queries) ================= */
@media (max-width: 768px) {
  .topbar {
    top: 12px; left: 12px; right: 12px;
    padding: 0 12px;
  }
  
  .brand-title span:first-child {
    display: none; /* 手机端空间小，隐藏 TideBot，只保留 控制台/chat */
  }
  
  .app-connect-btn {
    padding: 6px 12px;
    font-size: 12px;
  }
  
  .main-content {
    top: 84px;
    left: 12px; right: 12px; bottom: 12px;
  }

  .sidebar {
    left: -260px; /* 默认隐藏侧边栏 */
    top: 12px;
    bottom: 12px;
    box-shadow: 10px 0 30px rgba(0,0,0,0.1);
  }

  .sidebar.open {
    transform: translateX(272px); /* 滑出 */
  }

  .sidebar-overlay {
    display: block;
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.4);
    backdrop-filter: blur(4px);
    opacity: 0;
    pointer-events: none;
    z-index: 89;
    transition: opacity 0.3s ease;
  }
  
  .sidebar-overlay.show {
    opacity: 1;
    pointer-events: auto;
  }
}
</style>