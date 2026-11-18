<script setup lang="ts">
definePageMeta({ layout: false })
const user = useSupabaseUser()
watch(user, () => { if (user.value) navigateTo('/') }, { immediate: true })
</script>

<template>
  <div class="flex min-h-dvh items-center justify-center font-sans text-neutro-texto">
    Confirmando seu acesso…
  </div>
</template>
