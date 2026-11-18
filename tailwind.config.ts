import type { Config } from 'tailwindcss'

export default {
  content: ['./app/**/*.{vue,js,ts}'],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Outfit', 'system-ui', 'sans-serif'],
      },
      colors: {
        lojao: {
          DEFAULT: '#E30613', // vermelho da marca
          escuro: '#B0000F',  // hover / pressionado
          claro: '#FDECEE',   // fundo de alerta
        },
        grafite: '#232327',   // texto principal
        neutro: {
          texto: '#5E5E66',
          linha: '#E2E2E6',
        },
      },
    },
  },
  plugins: [],
} satisfies Config
