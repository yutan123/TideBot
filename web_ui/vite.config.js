import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import path from 'path'

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src')
    }
  },
  // 新增打包配置
  build: {
    // 假设你的前端文件夹和后端代码在同一个父目录下
    // 将打包产物直接输出到上层目录的 web_ui 文件夹中
    outDir: '../web_ui', 
    emptyOutDir: true // 打包前自动清空旧文件
  },
  server: {
    host: '0.0.0.0',
    port: 3000
  }
})