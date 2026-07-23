<template>
  <div 
    class="ios-switch" 
    :class="{ 'active': modelValue }"
    @click="$emit('update:modelValue', !modelValue)"
  >
    <div class="switch-knob"></div>
  </div>
</template>

<script setup>
defineProps({
  modelValue: {
    type: Boolean,
    default: false
  }
})
defineEmits(['update:modelValue'])
</script>

<style scoped>
.ios-switch {
  width: 50px;
  height: 30px;
  background-color: var(--switch-bg);
  border-radius: var(--radius-pill);
  position: relative;
  cursor: pointer;
  transition: background-color 0.3s var(--ease-out);
  box-shadow: inset 0 1px 3px rgba(0,0,0,0.1);
}
.ios-switch.active {
  background-color: var(--primary);
}
.switch-knob {
  position: absolute;
  top: 2px;
  left: 2px;
  width: 26px;
  height: 26px;
  background-color: #ffffff;
  border-radius: 50%;
  box-shadow: 0 2px 4px rgba(0,0,0,0.2);
  transition: transform 0.3s var(--spring);
}
.ios-switch.active .switch-knob {
  transform: translateX(20px);
}
</style>