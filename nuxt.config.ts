// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  devtools: { enabled: true },

  modules: ['@nuxtjs/supabase', '@nuxtjs/tailwindcss'],

  app: {
    head: {
      htmlAttrs: { lang: 'pt-BR' },
      title: 'Controladoria Lojão',
      link: [
        { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
        { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' },
        { rel: 'stylesheet', href: 'https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700&display=swap' },
      ],
    },
  },

  tailwindcss: {
    cssPath: '~/assets/css/tailwind.css',
  },

  postcss: {
    plugins: {
      // Tailwind 3.4 não exporta mais o plugin de nesting nesse caminho
      'tailwindcss/nesting': false,
    },
  },

  supabase: {
    // Rotas exigem login; quem não estiver autenticado vai para /login
    redirect: true,
    redirectOptions: {
      login: '/login',
      callback: '/confirm',
      exclude: [],
    },
  },
})
