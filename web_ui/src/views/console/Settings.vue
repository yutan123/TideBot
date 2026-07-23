<template>
  <div class="view-container">
    <GlassCard>
      <h2>全局设置</h2>
      
      <div class="settings-group">
        <div class="setting-item">
          <div class="info">
            <h4>开发者模式</h4>
            <p>开启后将显示额外的调试信息</p>
          </div>
          <IosSwitch v-model="devMode" />
        </div>

        <div class="setting-item">
          <div class="info">
            <h4>消息自动保存</h4>
            <p>对话记录将自动持久化至本地</p>
          </div>
          <IosSwitch v-model="autoSave" />
        </div>
      </div>
    </GlassCard>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import GlassCard from '@/components/ui/GlassCard.vue'
import IosSwitch from '@/components/ui/IosSwitch.vue'

const devMode = ref(false)
const autoSave = ref(true)
</script>

<style scoped>
.view-container {
  padding: 24px;
  max-width: 800px;
  margin: 0 auto;
}
.settings-group {
  margin-top: 24px;
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.setting-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 16px;
  background: rgba(150, 150, 150, 0.05);
  border-radius: var(--radius-md);
  border: 1px solid var(--glass-border);
}
.info h4 { margin-bottom: 4px; font-weight: 600; }
.info p { font-size: 13px; color: var(--text-secondary); }
</style>