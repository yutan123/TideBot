import { defineStore } from 'pinia'

export const useAppStore = defineStore('app', {
  state: () => ({
    isDarkMode: false,
    isChatMode: false, // false = 控制台, true = Chat
    isSidebarOpen: false
  }),
  actions: {
    toggleTheme() {
      this.isDarkMode = !this.isDarkMode
      if (this.isDarkMode) {
        document.documentElement.classList.add('dark')
      } else {
        document.documentElement.classList.remove('dark')
      }
    },
    setMode(mode) {
      this.isChatMode = mode === 'chat'
    },
    toggleSidebar() {
      this.isSidebarOpen = !this.isSidebarOpen
    },
    closeSidebar() {
      this.isSidebarOpen = false
    }
  }
})