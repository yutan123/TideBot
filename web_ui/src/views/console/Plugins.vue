<template>
  <div class="view-container">
    <div class="header-actions">
      <h2>插件市场</h2>
    </div>

    <div class="plugins-grid">
      <GlassCard class="plugin-card">
        <div class="plugin-header">
          <div class="plugin-icon">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M12 2v20M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"></path>
            </svg>
          </div>
          <IosSwitch :modelValue="false" />
        </div>
        <h4 class="plugin-title">联网搜索</h4>
        <p class="plugin-desc">允许 TideBot 实时搜索互联网获取最新资讯。</p>
      </GlassCard>

      <GlassCard class="plugin-card">
        <div class="plugin-header">
          <div class="plugin-icon">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <rect x="3" y="3" width="18" height="18" rx="2" ry="2"></rect>
              <circle cx="8.5" cy="8.5" r="1.5"></circle>
              <polyline points="21 15 16 10 5 21"></polyline>
            </svg>
          </div>
          <IosSwitch :modelValue="false" />
        </div>
        <h4 class="plugin-title">图像生成</h4>
        <p class="plugin-desc">调用外部 API 根据文字描述绘制图像。</p>
      </GlassCard>
    </div>
  </div>
</template>

<script setup>
import GlassCard from '@/components/ui/GlassCard.vue'
import IosSwitch from '@/components/ui/IosSwitch.vue'
</script>

<style scoped>
.view-container {
  padding: 24px;
}
.header-actions {
  margin-bottom: 24px;
}
.plugins-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 20px;
}
.plugin-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 16px;
}
.plugin-icon {
  width: 48px;
  height: 48px;
  border-radius: var(--radius-md);
  background: var(--primary);
  color: white;
  display: flex;
  align-items: center;
  justify-content: center;
}
.plugin-title {
  font-weight: 600;
  margin-bottom: 8px;
  font-size: 16px;
}
.plugin-desc {
  font-size: 13px;
  color: var(--text-secondary);
  line-height: 1.5;
}
</style>