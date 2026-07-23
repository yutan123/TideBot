import { createRouter, createWebHistory } from 'vue-router'
import { useAppStore } from '@/stores/appStore'

const routes = [
  {
    path: '/',
    redirect: '/console/dashboard'
  },
  {
    path: '/chat',
    name: 'Chat',
    component: () => import('@/views/ChatView.vue')
  },
  {
    path: '/app-connect',
    name: 'AppConnect',
    component: () => import('@/views/AppConnectView.vue')
  },
  {
    path: '/console/dashboard',
    name: 'Dashboard',
    component: () => import('@/views/console/Dashboard.vue')
  },
  {
    path: '/console/providers',
    name: 'ModelProviders',
    component: () => import('@/views/console/ModelProviders.vue')
  }
  // 后续继续补全 Settings, Plugins 等路由
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

// 路由守卫：联动 Pinia 状态
router.beforeEach((to, from, next) => {
  const store = useAppStore()
  if (to.path.startsWith('/chat')) {
    store.setMode('chat')
  } else {
    store.setMode('console')
  }
  // 切换路由时自动收起手机端侧边栏
  store.closeSidebar()
  next()
})

export default router