<template>
  <div class="view-container">
    <div class="header-actions">
      <h2>模型提供商</h2>
      <button class="btn-primary btn-spring">+ 添加配置</button>
    </div>

    <div class="provider-categories">
      <!-- LLM 分类 -->
      <GlassCard class="category-card">
        <h3>大语言模型 (LLM)</h3>
        <div class="empty-state">暂无配置的大模型</div>
      </GlassCard>

      <!-- TTS 分类 -->
      <GlassCard class="category-card">
        <h3>语音合成 (TTS)</h3>
        <div class="empty-state">暂无配置的 TTS 模型</div>
      </GlassCard>
      
      <!-- 语音识别 (SST) 和 Agent 分类... -->
    </div>
  </div>
</template>

<script setup>
import GlassCard from '@/components/ui/GlassCard.vue'
</script>

<style scoped>
.view-container {
  padding: 24px;
}
.header-actions {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 24px;
}
.btn-primary {
  background: var(--primary);
  color: white;
  padding: 8px 16px;
  border-radius: var(--radius-pill);
  font-weight: 600;
}
.provider-categories {
  display: flex;
  flex-direction: column;
  gap: 24px;
}
.category-card h3 {
  margin-bottom: 16px;
  padding-bottom: 12px;
  border-bottom: 1px solid var(--glass-border);
}
.empty-state {
  padding: 32px 0;
  text-align: center;
  color: var(--text-secondary);
  font-size: 14px;
}
</style>