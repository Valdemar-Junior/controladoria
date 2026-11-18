<script setup lang="ts">
const supabase = useSupabaseClient()
const user = useSupabaseUser()

const menu = [
  { para: '/', rotulo: 'Início' },
  { para: '/despesas', rotulo: 'Despesas' },
  { para: '/classificacao', rotulo: 'Classificação de despesas' },
]

async function sair() {
  await supabase.auth.signOut()
  await navigateTo('/login')
}
</script>

<template>
  <div class="min-h-dvh font-sans text-grafite">
    <header class="flex items-center justify-between gap-6 border-b border-neutro-linha bg-white px-6 py-3">
      <div class="flex items-center gap-8">
        <NuxtLink to="/" class="font-semibold"><span class="text-lojao">Controladoria</span> Lojão</NuxtLink>
        <nav class="flex gap-1 text-sm">
          <NuxtLink
            v-for="item in menu"
            :key="item.para"
            :to="item.para"
            class="rounded-lg px-3 py-1.5 font-medium text-neutro-texto hover:bg-lojao-claro hover:text-lojao-escuro"
            exact-active-class="!bg-lojao-claro !text-lojao-escuro"
          >
            {{ item.rotulo }}
          </NuxtLink>
        </nav>
      </div>
      <div class="flex items-center gap-4 text-sm">
        <span class="text-neutro-texto">{{ user?.email }}</span>
        <button class="rounded-lg px-3 py-1.5 font-medium hover:bg-lojao-claro hover:text-lojao-escuro" @click="sair">
          Sair
        </button>
      </div>
    </header>
    <main class="p-6">
      <slot />
    </main>
  </div>
</template>
