<template>
  <header class="topbar">
    <div class="topbar-left">
      <IconButton class="hamburger" @click="store.toggleSidebar">
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round">
          <line x1="3" y1="12" x2="21" y2="12"></line>
          <line x1="3" y1="6" x2="21" y2="6"></line>
          <line x1="3" y1="18" x2="21" y2="18"></line>
        </svg>
      </IconButton>
      
      <div class="brand-title">
        <span>TideBot</span>
        <span class="brand-subtitle" :class="{ 'is-chat': store.isChatMode }">
          {{ store.isChatMode ? 'chat' : '控制台' }}
        </span>
      </div>
    </div>

    <div class="topbar-right">
      <button class="app-connect-btn btn-spring" @click="router.push('/app-connect')">
        连接 APP
      </button>

      <IconButton @click="store.toggleTheme">
        <svg v-if="!store.isDarkMode" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
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
      </IconButton>

      <div class="mode-switch-wrapper" @click="toggleMode">
        <div class="mode-switch" :class="{ 'active': store.isChatMode }">
          <div class="switch-knob">
            {{ store.isChatMode ? 'chat' : '控制台' }}
          </div>
        </div>
      </div>
    </div>
  </header>
</template>

<script setup>
import { useRouter } from 'vue-router'
import { useAppStore } from '@/stores/appStore'
import IconButton from '@/components/ui/IconButton.vue'

const store = useAppStore()
const router = useRouter()

const toggleMode = () => {
  if (store.isChatMode) {
    router.push('/console/dashboard')
  } else {
    router.push('/chat')
  }
}
</script>

<style scoped>
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
  border-radius: var(--radius-pill);
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
.app-connect-btn {
  background: var(--primary);
  color: #fff;
  padding: 8px 16px;
  border-radius: var(--radius-pill);
  font-size: 14px;
  font-weight: 600;
  box-shadow: 0 4px 12px rgba(0, 122, 255, 0.3);
}
.mode-switch-wrapper {
  cursor: pointer;
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
  box-shadow: 0 2px 8px rgba(0,0,0,0.15);
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

@media (max-width: 768px) {
  .topbar {
    top: 12px; left: 12px; right: 12px;
  }
  .brand-title span:first-child { display: none; }
  .app-connect-btn { padding: 6px 12px; font-size: 12px; }
}
</style>