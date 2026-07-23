<template>
  <button class="icon-btn btn-spring" @click="$emit('click')">
    <slot></slot>
  </button>
</template>

<script setup>
defineEmits(['click'])
</script>

<style scoped>
.icon-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-main);
  opacity: 0.8;
  padding: 8px;
  border-radius: var(--radius-sm);
}
.icon-btn:hover {
  background: rgba(150, 150, 150, 0.1);
  opacity: 1;
}
</style>