<template>
  <div class="view-container">
    <div class="header-actions">
      <h2>机器人 & 人格设定</h2>
      <button class="btn-primary btn-spring">+ 新建人格</button>
    </div>

    <GlassCard>
      <div class="empty-state">
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class="empty-icon">
          <circle cx="12" cy="12" r="10"></circle>
          <path d="M8 14s1.5 2 4 2 4-2 4-2"></path>
          <line x1="9" y1="9" x2="9.01" y2="9"></line>
          <line x1="15" y1="9" x2="15.01" y2="9"></line>
        </svg>
        <p>还没有设定专属机器人人格，快去创建一个吧！</p>
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
.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 60px 0;
  color: var(--text-secondary);
  text-align: center;
}
.empty-icon {
  margin-bottom: 16px;
  opacity: 0.5;
}
</style>