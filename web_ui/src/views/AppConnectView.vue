<template>
  <div class="view-container">
    <GlassCard>
      <h2>连接手机 APP</h2>
      <p class="subtitle">通过以下方式将你的移动设备连接至 TideBot 核心。</p>
      
      <div class="connect-actions">
        <div class="action-item">
          <div class="info">
            <h4>生成 API 密钥</h4>
            <p>用于在 APP 端进行安全认证</p>
          </div>
          <button class="btn-primary btn-spring">生成 Key</button>
        </div>

        <div class="action-item">
          <div class="info">
            <h4>创建内网穿透</h4>
            <p>即使在外网也能安全访问本地环境</p>
          </div>
          <button class="btn-primary btn-spring">启动穿透</button>
        </div>
      </div>
    </GlassCard>
  </div>
</template>

<script setup>
import GlassCard from '@/components/ui/GlassCard.vue'
</script>

<style scoped>
.view-container {
  padding: 24px;
  max-width: 800px;
  margin: 0 auto;
}
.subtitle {
  color: var(--text-secondary);
  margin-bottom: 32px;
}
.connect-actions {
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.action-item {
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
.btn-primary {
  background: var(--primary);
  color: white;
  padding: 8px 16px;
  border-radius: var(--radius-pill);
  font-weight: 600;
}
</style>