<script setup lang="ts">
useHead({ title: 'Classificação de despesas · Controladoria Lojão' })

type Situacao = 'classificado' | 'fora' | 'pendente'
interface Linha {
  historico_id: number
  historico_erp: string
  situacao: Situacao
  grupo: string | null
  categoria: string | null
  subcategoria: string | null
  obs: string | null
  updated_at: string
}

const supabase = useSupabaseClient()

const SITUACOES: Record<Situacao, { rotulo: string, classe: string }> = {
  classificado: { rotulo: 'Classificado', classe: 'bg-emerald-50 text-emerald-700 ring-emerald-200' },
  pendente: { rotulo: 'Pendente', classe: 'bg-amber-50 text-amber-800 ring-amber-200' },
  fora: { rotulo: 'Não é despesa', classe: 'bg-slate-100 text-slate-600 ring-slate-200' },
}

// ---------- carregar ----------
const linhas = ref<Linha[]>([])
const carregando = ref(true)
const erroCarga = ref('')

async function carregar() {
  carregando.value = true
  erroCarga.value = ''
  const { data, error } = await supabase
    .from('de_para_historicos')
    .select('*')
    .order('grupo', { nullsFirst: true })
    .order('categoria')
    .order('subcategoria')
    .order('historico_id')
  carregando.value = false
  if (error) {
    erroCarga.value = error.code === '42P01' || error.message.includes('does not exist')
      ? 'A tabela de_para_historicos ainda não existe no Supabase. Rode a migration em supabase/migrations.'
      : `Não foi possível carregar: ${error.message}`
    return
  }
  linhas.value = (data ?? []) as Linha[]
}
onMounted(carregar)

// ---------- filtros ----------
const busca = ref('')
const filtroGrupo = ref('')
const filtroSituacao = ref<Situacao | ''>('')

const contagem = computed(() => {
  const c = { total: linhas.value.length, classificado: 0, pendente: 0, fora: 0 }
  for (const l of linhas.value) c[l.situacao]++
  return c
})

const grupos = computed(() => unicos(linhas.value.map(l => l.grupo)))

function normalizar(s: string) {
  return s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
}
function unicos(lista: (string | null)[]) {
  return [...new Set(lista.filter((v): v is string => !!v))].sort((a, b) => a.localeCompare(b, 'pt-BR'))
}

const filtradas = computed(() => {
  const termo = normalizar(busca.value.trim())
  return linhas.value.filter((l) => {
    if (filtroGrupo.value && l.grupo !== filtroGrupo.value) return false
    if (filtroSituacao.value && l.situacao !== filtroSituacao.value) return false
    if (!termo) return true
    const texto = normalizar([l.historico_id, l.historico_erp, l.grupo, l.categoria, l.subcategoria, l.obs].join(' '))
    return texto.includes(termo)
  })
})

// ---------- formulário (novo / editar) ----------
const formAberto = ref(false)
const editando = ref<number | null>(null) // historico_id em edição; null = novo
const salvando = ref(false)
const erroForm = ref('')
const form = reactive({
  historico_id: null as number | null,
  historico_erp: '',
  situacao: 'classificado' as Situacao,
  grupo: '',
  categoria: '',
  subcategoria: '',
  obs: '',
})

// sugestões para manter a mesma grafia que o financeiro já usa
const sugestoesCategoria = computed(() =>
  unicos(linhas.value.filter(l => !form.grupo || l.grupo === form.grupo).map(l => l.categoria)))
const sugestoesSubcategoria = computed(() =>
  unicos(linhas.value
    .filter(l => (!form.grupo || l.grupo === form.grupo) && (!form.categoria || l.categoria === form.categoria))
    .map(l => l.subcategoria)))

function abrirNovo() {
  editando.value = null
  Object.assign(form, { historico_id: null, historico_erp: '', situacao: 'classificado', grupo: '', categoria: '', subcategoria: '', obs: '' })
  erroForm.value = ''
  formAberto.value = true
}

function abrirEdicao(l: Linha) {
  editando.value = l.historico_id
  Object.assign(form, {
    historico_id: l.historico_id,
    historico_erp: l.historico_erp,
    situacao: l.situacao,
    grupo: l.grupo ?? '',
    categoria: l.categoria ?? '',
    subcategoria: l.subcategoria ?? '',
    obs: l.obs ?? '',
  })
  erroForm.value = ''
  formAberto.value = true
}

function vazioParaNull(s: string) {
  const t = s.trim()
  return t === '' ? null : t
}

async function salvar() {
  erroForm.value = ''
  if (!form.historico_id || form.historico_id <= 0) return (erroForm.value = 'Informe o código do histórico no ERP.')
  if (!form.historico_erp.trim()) return (erroForm.value = 'Informe a descrição do histórico.')
  if (form.situacao === 'classificado' && (!form.grupo.trim() || !form.categoria.trim()))
    return (erroForm.value = 'Para classificar, escolha pelo menos o grupo e a categoria.')

  const classificado = form.situacao === 'classificado'
  const registro = {
    historico_id: form.historico_id,
    historico_erp: form.historico_erp.trim(),
    situacao: form.situacao,
    grupo: classificado ? vazioParaNull(form.grupo) : null,
    categoria: classificado ? vazioParaNull(form.categoria) : null,
    subcategoria: classificado ? vazioParaNull(form.subcategoria) : null,
    obs: vazioParaNull(form.obs),
  }

  salvando.value = true
  const { error } = editando.value === null
    ? await supabase.from('de_para_historicos').insert(registro)
    : await supabase.from('de_para_historicos').update(registro).eq('historico_id', editando.value)
  salvando.value = false

  if (error) {
    erroForm.value = error.code === '23505'
      ? `O histórico ${form.historico_id} já está cadastrado. Procure por ele na lista e edite.`
      : `Não foi possível salvar: ${error.message}`
    return
  }
  formAberto.value = false
  await carregar()
}

// ---------- excluir ----------
const paraExcluir = ref<Linha | null>(null)
const excluindo = ref(false)

async function confirmarExclusao() {
  if (!paraExcluir.value) return
  excluindo.value = true
  const { error } = await supabase.from('de_para_historicos').delete().eq('historico_id', paraExcluir.value.historico_id)
  excluindo.value = false
  if (error) {
    erroCarga.value = `Não foi possível excluir: ${error.message}`
  }
  else {
    linhas.value = linhas.value.filter(l => l.historico_id !== paraExcluir.value!.historico_id)
  }
  paraExcluir.value = null
}

function fecharModais(e: KeyboardEvent) {
  if (e.key !== 'Escape') return
  formAberto.value = false
  paraExcluir.value = null
}
onMounted(() => window.addEventListener('keydown', fecharModais))
onBeforeUnmount(() => window.removeEventListener('keydown', fecharModais))
</script>

<template>
  <div class="mx-auto max-w-7xl">
    <!-- título -->
    <div class="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 class="text-2xl font-semibold">Classificação de despesas</h1>
        <p class="mt-1 max-w-2xl text-sm text-neutro-texto">
          Cada histórico de despesa do ERP vai para um grupo, categoria e subcategoria, do mesmo jeito da planilha mensal do financeiro.
          Quando aparecer um histórico novo no ERP, cadastre aqui uma vez e ele passa a ser classificado sozinho.
        </p>
      </div>
      <button
        class="rounded-lg bg-lojao px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-lojao-escuro"
        @click="abrirNovo"
      >
        + Novo histórico
      </button>
    </div>

    <!-- contadores (também filtram) -->
    <div class="mb-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
      <button
        v-for="item in ([
          { chave: '', rotulo: 'Todos', valor: contagem.total },
          { chave: 'classificado', rotulo: 'Classificados', valor: contagem.classificado },
          { chave: 'pendente', rotulo: 'Pendentes', valor: contagem.pendente },
          { chave: 'fora', rotulo: 'Não são despesa', valor: contagem.fora },
        ] as const)"
        :key="item.chave"
        class="rounded-xl border bg-white px-4 py-3 text-left transition"
        :class="filtroSituacao === item.chave ? 'border-lojao ring-1 ring-lojao' : 'border-neutro-linha hover:border-slate-300'"
        @click="filtroSituacao = item.chave"
      >
        <div class="text-xs font-medium uppercase tracking-wide text-neutro-texto">{{ item.rotulo }}</div>
        <div class="mt-1 text-2xl font-semibold tabular-nums" :class="item.chave === 'pendente' && item.valor > 0 ? 'text-amber-700' : ''">
          {{ item.valor }}
        </div>
      </button>
    </div>

    <!-- filtros -->
    <div class="mb-3 flex flex-wrap gap-3">
      <input
        v-model="busca"
        type="search"
        placeholder="Buscar por código, histórico, categoria…"
        class="min-w-64 flex-1 rounded-lg border border-neutro-linha bg-white px-3 py-2 text-sm outline-none focus:border-lojao focus:ring-1 focus:ring-lojao"
      >
      <select
        v-model="filtroGrupo"
        class="rounded-lg border border-neutro-linha bg-white px-3 py-2 text-sm outline-none focus:border-lojao"
      >
        <option value="">Todos os grupos</option>
        <option v-for="g in grupos" :key="g" :value="g">{{ g }}</option>
      </select>
    </div>

    <p v-if="erroCarga" class="mb-3 rounded-lg bg-lojao-claro px-4 py-3 text-sm text-lojao-escuro">{{ erroCarga }}</p>

    <!-- tabela -->
    <div class="overflow-hidden rounded-xl border border-neutro-linha bg-white">
      <table class="w-full text-sm">
        <thead class="bg-slate-50 text-left text-xs uppercase tracking-wide text-neutro-texto">
          <tr>
            <th class="px-4 py-3 font-medium">Cód.</th>
            <th class="px-4 py-3 font-medium">Histórico no ERP</th>
            <th class="px-4 py-3 font-medium">Classificação</th>
            <th class="px-4 py-3 font-medium">Situação</th>
            <th class="px-4 py-3" />
          </tr>
        </thead>
        <tbody class="divide-y divide-neutro-linha">
          <tr v-if="carregando">
            <td colspan="5" class="px-4 py-10 text-center text-neutro-texto">Carregando…</td>
          </tr>
          <tr v-else-if="!filtradas.length">
            <td colspan="5" class="px-4 py-10 text-center text-neutro-texto">Nenhum histórico encontrado com esses filtros.</td>
          </tr>
          <tr v-for="l in filtradas" v-else :key="l.historico_id" class="group align-top hover:bg-slate-50">
            <td class="px-4 py-3 font-mono text-xs text-neutro-texto tabular-nums">{{ l.historico_id }}</td>
            <td class="px-4 py-3">
              <div class="font-medium">{{ l.historico_erp }}</div>
              <div v-if="l.obs" class="mt-0.5 text-xs text-neutro-texto">{{ l.obs }}</div>
            </td>
            <td class="px-4 py-3">
              <template v-if="l.grupo">
                <div class="text-xs font-semibold uppercase tracking-wide text-neutro-texto">{{ l.grupo }}</div>
                <div>
                  {{ l.categoria }}<span v-if="l.subcategoria" class="text-neutro-texto"> › {{ l.subcategoria }}</span>
                </div>
              </template>
              <span v-else class="text-neutro-texto">—</span>
            </td>
            <td class="px-4 py-3">
              <span class="inline-flex rounded-full px-2 py-0.5 text-xs font-medium ring-1" :class="SITUACOES[l.situacao].classe">
                {{ SITUACOES[l.situacao].rotulo }}
              </span>
            </td>
            <td class="whitespace-nowrap px-4 py-3 text-right">
              <button class="rounded-md px-2 py-1 font-medium text-grafite hover:bg-lojao-claro hover:text-lojao-escuro" @click="abrirEdicao(l)">
                Editar
              </button>
              <button class="rounded-md px-2 py-1 font-medium text-neutro-texto hover:bg-lojao-claro hover:text-lojao-escuro" @click="paraExcluir = l">
                Excluir
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <p v-if="!carregando" class="mt-2 text-xs text-neutro-texto">{{ filtradas.length }} de {{ contagem.total }} históricos</p>

    <!-- modal: novo / editar -->
    <div v-if="formAberto" class="fixed inset-0 z-40 flex items-start justify-center overflow-y-auto bg-black/40 p-4 pt-16" @click.self="formAberto = false">
      <form class="w-full max-w-lg rounded-2xl bg-white p-6 shadow-xl" @submit.prevent="salvar">
        <h2 class="text-lg font-semibold">{{ editando === null ? 'Novo histórico' : `Editar histórico ${editando}` }}</h2>

        <div class="mt-5 grid grid-cols-[7rem_1fr] gap-3">
          <label class="text-sm">
            <span class="mb-1 block font-medium">Código no ERP</span>
            <input
              v-model.number="form.historico_id"
              type="number"
              min="1"
              :disabled="editando !== null"
              class="w-full rounded-lg border border-neutro-linha px-3 py-2 outline-none focus:border-lojao disabled:bg-slate-50 disabled:text-neutro-texto"
            >
          </label>
          <label class="text-sm">
            <span class="mb-1 block font-medium">Histórico no ERP</span>
            <input v-model="form.historico_erp" class="w-full rounded-lg border border-neutro-linha px-3 py-2 outline-none focus:border-lojao">
          </label>
        </div>

        <fieldset class="mt-4">
          <legend class="mb-1 text-sm font-medium">Situação</legend>
          <div class="flex flex-wrap gap-2">
            <label
              v-for="(s, chave) in SITUACOES"
              :key="chave"
              class="cursor-pointer rounded-lg border px-3 py-1.5 text-sm"
              :class="form.situacao === chave ? 'border-lojao bg-lojao-claro font-medium text-lojao-escuro' : 'border-neutro-linha'"
            >
              <input v-model="form.situacao" type="radio" :value="chave" class="sr-only">
              {{ s.rotulo }}
            </label>
          </div>
        </fieldset>

        <div v-if="form.situacao === 'classificado'" class="mt-4 space-y-3">
          <label class="block text-sm">
            <span class="mb-1 block font-medium">Grupo</span>
            <input v-model="form.grupo" list="lista-grupos" placeholder="ex.: PESSOAL" class="w-full rounded-lg border border-neutro-linha px-3 py-2 outline-none focus:border-lojao">
          </label>
          <label class="block text-sm">
            <span class="mb-1 block font-medium">Categoria</span>
            <input v-model="form.categoria" list="lista-categorias" placeholder="ex.: Alimentação" class="w-full rounded-lg border border-neutro-linha px-3 py-2 outline-none focus:border-lojao">
          </label>
          <label class="block text-sm">
            <span class="mb-1 block font-medium">Subcategoria <span class="font-normal text-neutro-texto">(opcional)</span></span>
            <input v-model="form.subcategoria" list="lista-subcategorias" class="w-full rounded-lg border border-neutro-linha px-3 py-2 outline-none focus:border-lojao">
          </label>
          <p class="text-xs text-neutro-texto">Comece a digitar para ver as opções que já existem. Use a mesma grafia para não criar categorias repetidas.</p>
          <datalist id="lista-grupos"><option v-for="g in grupos" :key="g" :value="g" /></datalist>
          <datalist id="lista-categorias"><option v-for="c in sugestoesCategoria" :key="c" :value="c" /></datalist>
          <datalist id="lista-subcategorias"><option v-for="s in sugestoesSubcategoria" :key="s" :value="s" /></datalist>
        </div>

        <label class="mt-4 block text-sm">
          <span class="mb-1 block font-medium">Observação <span class="font-normal text-neutro-texto">(opcional)</span></span>
          <textarea v-model="form.obs" rows="2" class="w-full rounded-lg border border-neutro-linha px-3 py-2 outline-none focus:border-lojao" />
        </label>

        <p v-if="erroForm" class="mt-4 rounded-lg bg-lojao-claro px-3 py-2 text-sm text-lojao-escuro">{{ erroForm }}</p>

        <div class="mt-6 flex justify-end gap-2">
          <button type="button" class="rounded-lg px-4 py-2 text-sm font-medium hover:bg-slate-100" @click="formAberto = false">Cancelar</button>
          <button type="submit" :disabled="salvando" class="rounded-lg bg-lojao px-4 py-2 text-sm font-semibold text-white hover:bg-lojao-escuro disabled:opacity-60">
            {{ salvando ? 'Salvando…' : 'Salvar' }}
          </button>
        </div>
      </form>
    </div>

    <!-- modal: confirmar exclusão -->
    <div v-if="paraExcluir" class="fixed inset-0 z-40 flex items-center justify-center bg-black/40 p-4" @click.self="paraExcluir = null">
      <div class="w-full max-w-md rounded-2xl bg-white p-6 shadow-xl">
        <h2 class="text-lg font-semibold">Excluir histórico {{ paraExcluir.historico_id }}?</h2>
        <p class="mt-2 text-sm text-neutro-texto">
          “{{ paraExcluir.historico_erp }}” deixa de ser classificado. As despesas com esse histórico vão aparecer como sem classificação.
        </p>
        <div class="mt-6 flex justify-end gap-2">
          <button class="rounded-lg px-4 py-2 text-sm font-medium hover:bg-slate-100" @click="paraExcluir = null">Cancelar</button>
          <button :disabled="excluindo" class="rounded-lg bg-lojao px-4 py-2 text-sm font-semibold text-white hover:bg-lojao-escuro disabled:opacity-60" @click="confirmarExclusao">
            {{ excluindo ? 'Excluindo…' : 'Excluir' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
