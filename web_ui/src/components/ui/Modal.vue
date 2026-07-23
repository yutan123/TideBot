<template>
  <Teleport to="body">
    <Transition name="modal">
      <div v-if="isOpen" class="modal-overlay" @click.self="close">
        <div class="modal-content glass-card">
          <h3 v-if="title" class="modal-title">{{ title }}</h3>
          <div class="modal-body">
            <slot></slot>
          </div>
          <div class="modal-actions">
            <button class="btn-cancel btn-spring" @click="close">取消</button>
            <button class="btn-confirm btn-spring" @click="$emit('confirm')">确认</button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup>
defineProps({
  isOpen: Boolean,
  title: String
})
const emit = defineEmits(['update:isOpen', 'confirm'])

const close = () => {
  emit('update:isOpen', false)
}
</script>

<style scoped>
.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.4);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
}
.modal-content {
  width: 90%;
  max-width: 400px;
  padding: 24px;
  border-radius: var(--radius-lg);
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.modal-title {
  font-size: 18px;
  font-weight: 600;
  text-align: center;
}
.modal-actions {
  display: flex;
  gap: 12px;
  margin-top: 8px;
}
.modal-actions button {
  flex: 1;
  padding: 12px;
  border-radius: var(--radius-sm);
  font-weight: 600;
  font-size: 15px;
}
.btn-cancel {
  background: rgba(150, 150, 150, 0.2);
  color: var(--text-main);
}
.btn-confirm {
  background: var(--primary);
  color: #fff;
}

/* 弹出动画 */
.modal-enter-active,
.modal-leave-active {
  transition: opacity 0.3s ease;
}
.modal-enter-active .modal-content,
.modal-leave-active .modal-content {
  transition: transform 0.3s var(--spring);
}
.modal-enter-from {
  opacity: 0;
}
.modal-enter-from .modal-content {
  transform: scale(0.9);
}
.modal-leave-to {
  opacity: 0;
}
.modal-leave-to .modal-content {
  transform: scale(0.9);
}
</style>