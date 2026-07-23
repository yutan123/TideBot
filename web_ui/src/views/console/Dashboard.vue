<template>
  <div class="view-container">
    <div class="dashboard-grid">
      <GlassCard class="stat-card">
        <h3>系统负载</h3>
        <div class="value">0 <span class="unit">%</span></div>
        <p>CPU 使用率</p>
      </GlassCard>
      
      <GlassCard class="stat-card">
        <h3>内存占用</h3>
        <div class="value">0 <span class="unit">MB</span></div>
        <p>当前服务消耗</p>
      </GlassCard>
      
      <GlassCard class="stat-card">
        <h3>API 请求数</h3>
        <div class="value">0</div>
        <p>今日累计调用</p>
      </GlassCard>
    </div>

    <GlassCard class="chart-card">
      <h3>运行状态总览</h3>
      <div class="placeholder-chart">
        <p>图表组件加载区...</p>
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
.dashboard-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
  gap: 24px;
  margin-bottom: 24px;
}
.stat-card h3 {
  font-size: 15px;
  color: var(--text-secondary);
  margin-bottom: 12px;
}
.stat-card .value {
  font-size: 32px;
  font-weight: 700;
  margin-bottom: 8px;
}
.stat-card .unit {
  font-size: 16px;
  font-weight: 500;
}
.stat-card p {
  font-size: 13px;
  color: var(--text-secondary);
}
.placeholder-chart {
  height: 200px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(150, 150, 150, 0.05);
  border-radius: var(--radius-md);
  margin-top: 16px;
  color: var(--text-secondary);
}
</style>