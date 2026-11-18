<script setup lang="ts">
definePageMeta({ layout: false })
useHead({ title: 'Entrar · Controladoria Lojão' })

const supabase = useSupabaseClient()
const user = useSupabaseUser()

const email = ref('')
const senha = ref('')
const mostrarSenha = ref(false)
const enviando = ref(false)
const erro = ref('')

// Já logado? Vai direto para o sistema.
watchEffect(() => {
  if (user.value) navigateTo('/')
})

const mensagens: Record<string, string> = {
  'Invalid login credentials': 'E-mail ou senha incorretos. Confira e tente de novo.',
  'Email not confirmed': 'Este e-mail ainda não foi confirmado. Verifique sua caixa de entrada.',
}

async function entrar() {
  erro.value = ''
  enviando.value = true
  const { error } = await supabase.auth.signInWithPassword({
    email: email.value.trim(),
    password: senha.value,
  })
  enviando.value = false

  if (error) {
    erro.value = mensagens[error.message]
      ?? 'Não foi possível entrar agora. Verifique sua conexão e tente de novo.'
    return
  }
  await navigateTo('/')
}
</script>

<template>
  <div class="min-h-dvh bg-white font-sans text-grafite lg:grid lg:grid-cols-[minmax(0,1.1fr)_minmax(26rem,1fr)]">
    <!-- Arte da Controladoria -->
    <aside class="relative overflow-hidden bg-grafite" aria-hidden="true">
      <!-- fundo: a mesma arte, ampliada e desfocada, para preencher qualquer proporção de tela -->
      <img
        src="/login2.jpg"
        alt=""
        class="absolute inset-0 hidden h-full w-full scale-110 object-cover opacity-70 blur-2xl lg:block"
      >
      <div class="absolute inset-0 hidden bg-gradient-to-br from-black/10 via-transparent to-lojao-escuro/40 lg:block" />

      <!-- celular: só o topo da arte (logo e título) -->
      <img
        src="/login2.jpg"
        alt=""
        class="aspect-[80/34] w-full object-cover object-top lg:hidden"
      >

      <!-- desktop: a arte inteira, sem cortes -->
      <div class="relative hidden h-full items-center justify-center p-10 lg:flex">
        <img
          src="/login2.jpg"
          alt=""
          class="arte max-h-[calc(100dvh-5rem)] w-auto rounded-[1.75rem] shadow-[0_30px_80px_-20px_rgba(80,0,8,0.55)] ring-1 ring-white/20"
        >
      </div>
    </aside>

    <!-- Formulário -->
    <main class="flex items-center justify-center px-6 py-10 sm:px-10 lg:py-0">
      <div class="w-full max-w-sm">
        <p class="hidden text-[0.95rem] font-medium text-lojao lg:block">Controladoria Lojão</p>
        <h1 class="mt-2 text-[2rem] font-semibold leading-tight tracking-tight">
          Entre na sua conta
        </h1>
        <p class="mt-3 text-[0.95rem] leading-relaxed text-neutro-texto">
          Use o e-mail e a senha que a controladoria cadastrou para você.
        </p>

        <form class="mt-9 space-y-5" novalidate @submit.prevent="entrar">
          <div>
            <label for="email" class="block text-sm font-medium">E-mail</label>
            <input
              id="email"
              v-model="email"
              type="email"
              autocomplete="email"
              required
              placeholder="nome@lojaodosmoveis.com.br"
              class="campo"
            >
          </div>

          <div>
            <label for="senha" class="block text-sm font-medium">Senha</label>
            <div class="relative">
              <input
                id="senha"
                v-model="senha"
                :type="mostrarSenha ? 'text' : 'password'"
                autocomplete="current-password"
                required
                class="campo pr-20"
              >
              <button
                type="button"
                class="absolute inset-y-0 right-0 mt-2 rounded-r-xl px-4 text-sm font-medium text-neutro-texto hover:text-grafite focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-lojao/40"
                :aria-pressed="mostrarSenha"
                @click="mostrarSenha = !mostrarSenha"
              >
                {{ mostrarSenha ? 'Ocultar' : 'Mostrar' }}
              </button>
            </div>
          </div>

          <p
            v-if="erro"
            role="alert"
            class="rounded-xl border-l-4 border-lojao bg-lojao-claro px-4 py-3 text-sm leading-snug text-lojao-escuro"
          >
            {{ erro }}
          </p>

          <button
            type="submit"
            :disabled="enviando || !email || !senha"
            class="mt-2 flex h-12 w-full items-center justify-center rounded-xl bg-lojao text-[1rem] font-semibold text-white transition-colors hover:bg-lojao-escuro focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-lojao/30 disabled:cursor-not-allowed disabled:bg-lojao/45"
          >
            {{ enviando ? 'Entrando…' : 'Entrar' }}
          </button>
        </form>

        <p class="mt-10 border-t border-neutro-linha pt-6 text-sm leading-relaxed text-neutro-texto">
          Sem acesso ou esqueceu a senha? Fale com o administrador da controladoria.
        </p>
      </div>
    </main>
  </div>
</template>

<style scoped>
.campo {
  @apply mt-2 block h-12 w-full rounded-xl border border-neutro-linha bg-white px-4 text-[1rem] text-grafite
    placeholder:text-neutro-texto/60 transition-[border-color,box-shadow]
    focus:border-lojao focus:outline-none focus:ring-4 focus:ring-lojao/15;
}

/* Único movimento da tela: a arte entra ao carregar */
.arte {
  animation: entrada 700ms cubic-bezier(0.2, 0.8, 0.2, 1) both;
}
@keyframes entrada {
  from { opacity: 0; transform: translateY(14px) scale(0.985); }
  to   { opacity: 1; transform: none; }
}
@media (prefers-reduced-motion: reduce) {
  .arte { animation: none; }
}
</style>
