<template>
  <aside class="sidebar" :class="{ 'open': store.isSidebarOpen }">
    <div class="sidebar-content">
      <div 
        v-for="item in menuItems" 
        :key="item.path"
        class="menu-item"
        :class="{ 'active': route.path.includes(item.path) }"
        @click="navigateTo(item.path)"
      >
        {{ item.name }}
      </div>
    </div>
  </aside>
  
  <div class="sidebar-overlay" :class="{ 'show': store.isSidebarOpen }" @click="store.closeSidebar"></div>
</template>

<script setup>
import { useRouter, useRoute } from 'vue-router'
import { useAppStore } from '@/stores/appStore'

const store = useAppStore()
const router = useRouter()
const route = useRoute()

const menuItems = [
  { name: '数据大盘', path: '/console/dashboard' },
  { name: '普通设置', path: '/console/settings' },
  { name: '高级设置', path: '/console/advanced' },
  { name: '模型提供商', path: '/console/providers' },
  { name: '平台适配器', path: '/console/adapters' },
  { name: '机器人', path: '/console/bots' },
  { name: '人格设定', path: '/console/personas' },
  { name: '插件市场', path: '/console/market' },
  { name: '插件列表', path: '/console/plugins' },
  { name: 'Skills', path: '/console/skills' }
]

const navigateTo = (path) => {
  router.push(path)
  store.closeSidebar()
}
</script>

<style scoped>
.sidebar {
  position: absolute;
  top: 92px;
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
  transition: transform 0.4s var(--spring), opacity 0.3s ease;
  overflow-y: auto;
}
.sidebar-content {
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.menu-item {
  padding: 12px 16px;
  border-radius: var(--radius-sm);
  font-size: 15px;
  font-weight: 500;
  color: var(--text-main);
  opacity: 0.7;
  cursor: pointer;
  transition: all 0.2s ease;
}
.menu-item:hover {
  background: rgba(150, 150, 150, 0.15);
  opacity: 1;
}
.menu-item.active {
  background: var(--primary);
  color: #fff;
  opacity: 1;
  box-shadow: 0 4px 12px rgba(0, 122, 255, 0.2);
}

.sidebar-overlay {
  display: none;
}

@media (max-width: 768px) {
  .sidebar {
    left: -260px;
    top: 12px;
    bottom: 12px;
  }
  .sidebar.open {
    transform: translateX(272px);
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