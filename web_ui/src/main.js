import { createApp } from 'vue'
import App from './App.vue'

// 引入全局样式体系 (严格按照层级)
import './assets/styles/variables.css'
import './assets/styles/base.css'
import './assets/styles/animations.css'

// 预留的状态管理与路由 (后续文件补齐后取消注释)
// import { createPinia } from 'pinia'
// import router from './router'

const app = createApp(App)

// app.use(createPinia())
// app.use(router)

app.mount('#app')