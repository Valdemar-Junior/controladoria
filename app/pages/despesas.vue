<script setup lang="ts">
useHead({ title: 'Despesas · Controladoria Lojão' })

interface Linha {
  mes: string // 'AAAA-MM-01'
  filial_id: number | null
  historico_id: number | null
  historico_erp: string
  situacao: 'classificado' | 'fora' | 'pendente'
  grupo: string | null
  categoria: string | null
  subcategoria: string | null
  qtd: number
  total: number // valor pago
  nominal: number // valor original dos títulos
}

const supabase = useSupabaseClient()

const FILIAIS: Record<number, string> = { 5: 'Assú', 6: 'Depósito', 9: 'Mossoró' }
const SEM_CLASSIFICACAO = 'SEM CLASSIFICAÇÃO'
const GRUPO_COMPRAS = 'COMPRAS E ESTOQUE'
const MESES_JANELA = 12

// ---------- formatação ----------
const brl = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })
function compacto(v: number) {
  const a = Math.abs(v)
  if (a >= 1e6) return `R$ ${(v / 1e6).toLocaleString('pt-BR', { maximumFractionDigits: 2 })} mi`
  if (a >= 1e3) return `R$ ${(v / 1e3).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} mil`
  return brl.format(v)
}
function nomeMes(iso: string, formato: 'curto' | 'longo' = 'curto') {
  const [a, m] = iso.split('-').map(Number)
  const d = new Date(a!, m! - 1, 1)
  const txt = d.toLocaleDateString('pt-BR', formato === 'curto' ? { month: 'short' } : { month: 'long', year: 'numeric' })
  return txt.replace('.', '').replace(/^./, c => c.toUpperCase())
}
function pct(parte: number, todo: number) {
  return todo ? `${((parte / todo) * 100).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%` : '—'
}

// ---------- carregar ----------
const linhas = ref<Linha[]>([])
const carregando = ref(true)
const erro = ref('')
const ultimaSync = ref<string | null>(null)

async function carregar() {
  carregando.value = true
  erro.value = ''
  const inicio = new Date()
  inicio.setDate(1)
  inicio.setMonth(inicio.getMonth() - (MESES_JANELA - 1))
  const desde = inicio.toISOString().slice(0, 10)

  const todas: Linha[] = []
  for (let de = 0; ; de += 1000) {
    const { data, error } = await supabase.from('vw_despesas_mensais').select('*')
      .gte('mes', desde).order('mes').order('historico_id').order('filial_id').range(de, de + 999)
    if (error) {
      erro.value = error.message.includes('does not exist')
        ? 'As tabelas de despesas ainda não existem no Supabase. Rode as migrations em supabase/migrations.'
        : `Não foi possível carregar: ${error.message}`
      carregando.value = false
      return
    }
    todas.push(...(data as Linha[]).map(l => ({ ...l, total: Number(l.total), nominal: Number(l.nominal) })))
    if (data.length < 1000) break
  }
  linhas.value = todas

  const { data: sync } = await supabase.from('sincronizacoes').select('finalizado_em')
    .is('erro', null).not('finalizado_em', 'is', null).order('finalizado_em', { ascending: false }).limit(1)
  ultimaSync.value = sync?.[0]?.finalizado_em ?? null

  carregando.value = false
  if (!mesSelecionado.value || !meses.value.includes(mesSelecionado.value)) {
    // abre no último mês fechado que tem dado (ou no mais recente)
    const hoje = new Date().toISOString().slice(0, 7)
    mesSelecionado.value = [...meses.value].reverse().find(m => m.slice(0, 7) < hoje) ?? meses.value.at(-1) ?? ''
  }
}
onMounted(carregar)

// ---------- filtros ----------
const filial = ref<number | 0>(0)
const incluirCompras = ref(false)
const mesSelecionado = ref('')
const grupoAberto = ref<string | null>(null)

const base = computed(() => linhas.value.filter(l =>
  l.situacao !== 'fora'
  && (!filial.value || l.filial_id === filial.value)
  && (incluirCompras.value || l.grupo !== GRUPO_COMPRAS)))

function grupoDe(l: Linha) { return l.situacao === 'pendente' ? SEM_CLASSIFICACAO : (l.grupo ?? SEM_CLASSIFICACAO) }
function soma(lista: Linha[], campo: 'total' | 'nominal' | 'qtd' = 'total') { return lista.reduce((s, l) => s + l[campo], 0) }

const meses = computed(() => [...new Set(linhas.value.map(l => l.mes))].sort())
const doMes = computed(() => base.value.filter(l => l.mes === mesSelecionado.value))

const mesAnterior = computed(() => {
  const i = meses.value.indexOf(mesSelecionado.value)
  return i > 0 ? meses.value[i - 1]! : null
})

// ---------- KPIs ----------
const kpi = computed(() => {
  const total = soma(doMes.value)
  const anterior = mesAnterior.value ? soma(base.value.filter(l => l.mes === mesAnterior.value)) : null
  const pend = doMes.value.filter(l => grupoDe(l) === SEM_CLASSIFICACAO)
  return {
    total,
    qtd: soma(doMes.value, 'qtd'),
    jurosDescontos: total - soma(doMes.value, 'nominal'), // >0 pagou juros, <0 teve desconto
    variacao: anterior ? (total - anterior) / anterior : null,
    pendenteValor: soma(pend),
    pendenteHistoricos: new Set(pend.map(l => l.historico_id)).size,
  }
})

// ---------- ranking de grupos do mês ----------
function agrupar(lista: Linha[], chave: (l: Linha) => string) {
  const m = new Map<string, number>()
  for (const l of lista) m.set(chave(l), (m.get(chave(l)) ?? 0) + l.total)
  return [...m].map(([nome, total]) => ({ nome, total })).sort((a, b) => b.total - a.total)
}
const gruposMes = computed(() => agrupar(doMes.value, grupoDe))
const maiorGrupo = computed(() => gruposMes.value[0]?.total ?? 0)

const categoriasGrupo = computed(() => {
  if (!grupoAberto.value) return []
  const doGrupo = doMes.value.filter(l => grupoDe(l) === grupoAberto.value)
  const cats = agrupar(doGrupo, l => l.categoria ?? l.historico_erp)
  return cats.map(c => ({
    ...c,
    subs: agrupar(doGrupo.filter(l => (l.categoria ?? l.historico_erp) === c.nome), l => l.subcategoria ?? '')
      .filter(s => s.nome),
  }))
})
const totalGrupoAberto = computed(() => gruposMes.value.find(g => g.nome === grupoAberto.value)?.total ?? 0)

// ---------- evolução mensal ----------
const evolucao = computed(() => meses.value.map(mes => ({
  mes,
  total: soma(base.value.filter(l => l.mes === mes && (!grupoAberto.value || grupoDe(l) === grupoAberto.value))),
})))
const maxEvolucao = computed(() => Math.max(...evolucao.value.map(e => e.total), 1))

// ---------- tabela (como a planilha) ----------
const expandidos = ref(new Set<string>())
function alternar(g: string) {
  const s = new Set(expandidos.value)
  s.has(g) ? s.delete(g) : s.add(g)
  expandidos.value = s
}
const tabela = computed(() => {
  const grupos = agrupar(base.value, grupoDe).map(g => g.nome)
  return grupos.map((g) => {
    const doGrupo = base.value.filter(l => grupoDe(l) === g)
    const porMes = (lista: Linha[]) => meses.value.map(m => soma(lista.filter(l => l.mes === m)))
    const cats = agrupar(doGrupo, l => l.categoria ?? l.historico_erp).map(c => {
      const daCat = doGrupo.filter(l => (l.categoria ?? l.historico_erp) === c.nome)
      return { nome: c.nome, valores: porMes(daCat), total: c.total }
    })
    return { nome: g, valores: porMes(doGrupo), total: soma(doGrupo), cats }
  })
})
const totaisTabela = computed(() => meses.value.map(m => soma(base.value.filter(l => l.mes === m))))

// ---------- tooltip ----------
const dica = ref<{ x: number, y: number, titulo: string, linhas: string[] } | null>(null)
function mostrarDica(e: MouseEvent, titulo: string, linhasDica: string[]) {
  dica.value = { x: e.clientX, y: e.clientY, titulo, linhas: linhasDica }
}
</script>

<template>
  <div class="mx-auto max-w-7xl">
    <!-- título + filtros -->
    <div class="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 class="text-2xl font-semibold">Despesas</h1>
        <p class="mt-1 text-sm text-neutro-texto">
          Contas a pagar quitadas, no mês do vencimento (a mesma base do Relatório Contas a Pagar do ERP), classificadas como na planilha do financeiro.
          <span v-if="ultimaSync">Atualizado em {{ new Date(ultimaSync).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' }) }}.</span>
        </p>
      </div>
      <div class="flex flex-wrap items-center gap-2 text-sm">
        <select v-model="mesSelecionado" class="rounded-lg border border-neutro-linha bg-white px-3 py-2 outline-none focus:border-lojao">
          <option v-for="m in meses" :key="m" :value="m">{{ nomeMes(m, 'longo') }}</option>
        </select>
        <div class="flex rounded-lg border border-neutro-linha bg-white p-0.5">
          <button
            v-for="(nome, id) in { 0: 'Todas', ...FILIAIS }"
            :key="id"
            class="rounded-md px-3 py-1.5 font-medium"
            :class="filial === Number(id) ? 'bg-lojao-claro text-lojao-escuro' : 'text-neutro-texto hover:text-grafite'"
            @click="filial = Number(id)"
          >
            {{ nome }}
          </button>
        </div>
        <label class="flex cursor-pointer items-center gap-2 rounded-lg border border-neutro-linha bg-white px-3 py-2">
          <input v-model="incluirCompras" type="checkbox" class="accent-lojao">
          Incluir compras de mercadoria
        </label>
      </div>
    </div>

    <p v-if="erro" class="mb-4 rounded-lg bg-lojao-claro px-4 py-3 text-sm text-lojao-escuro">{{ erro }}</p>

    <div v-if="carregando" class="rounded-xl border border-neutro-linha bg-white px-4 py-16 text-center text-neutro-texto">Carregando…</div>

    <div v-else-if="!erro && !meses.length" class="rounded-xl border border-neutro-linha bg-white px-6 py-16 text-center">
      <p class="font-medium">Ainda não há títulos copiados do ERP.</p>
      <p class="mt-1 text-sm text-neutro-texto">Execute no n8n o fluxo “Controladoria · Copiar contas a pagar do ERP para o Supabase”.</p>
    </div>

    <template v-else-if="!erro">
      <!-- aviso de pendentes -->
      <NuxtLink
        v-if="kpi.pendenteValor > 0"
        to="/classificacao"
        class="mb-4 flex items-center justify-between gap-4 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900 hover:border-amber-300"
      >
        <span>
          <strong>⚠ {{ compacto(kpi.pendenteValor) }}</strong> em {{ kpi.pendenteHistoricos }}
          {{ kpi.pendenteHistoricos === 1 ? 'histórico ainda não classificado' : 'históricos ainda não classificados' }} em {{ nomeMes(mesSelecionado, 'longo') }}.
        </span>
        <span class="font-semibold">Classificar →</span>
      </NuxtLink>

      <!-- KPIs -->
      <div class="mb-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <div class="rounded-xl border border-neutro-linha bg-white p-5 lg:col-span-2">
          <div class="text-xs font-medium uppercase tracking-wide text-neutro-texto">
            Total de {{ nomeMes(mesSelecionado, 'longo') }}{{ filial ? ` · ${FILIAIS[filial]}` : '' }}
          </div>
          <div class="mt-1 text-5xl font-semibold tabular-nums tracking-tight">{{ brl.format(kpi.total) }}</div>
          <div v-if="kpi.variacao !== null && mesAnterior" class="mt-2 text-sm text-neutro-texto">
            <span class="font-semibold" :class="kpi.variacao > 0 ? 'text-lojao-escuro' : 'text-emerald-700'">
              {{ kpi.variacao > 0 ? '▲' : '▼' }} {{ pct(Math.abs(kpi.variacao), 1) }}
            </span>
            em relação a {{ nomeMes(mesAnterior, 'longo') }}
          </div>
        </div>
        <div class="rounded-xl border border-neutro-linha bg-white p-5">
          <div class="text-xs font-medium uppercase tracking-wide text-neutro-texto">Títulos pagos</div>
          <div class="mt-1 text-2xl font-semibold tabular-nums">{{ kpi.qtd.toLocaleString('pt-BR') }}</div>
          <div class="mt-1 text-xs text-neutro-texto">média de {{ compacto(kpi.qtd ? kpi.total / kpi.qtd : 0) }} por título</div>
        </div>
        <div class="rounded-xl border border-neutro-linha bg-white p-5">
          <div class="text-xs font-medium uppercase tracking-wide text-neutro-texto">
            {{ kpi.jurosDescontos >= 0 ? 'Juros pagos' : 'Descontos obtidos' }}
          </div>
          <div class="mt-1 text-2xl font-semibold tabular-nums">{{ compacto(Math.abs(kpi.jurosDescontos)) }}</div>
          <div class="mt-1 text-xs text-neutro-texto">diferença entre o pago e o valor original dos títulos</div>
        </div>
      </div>

      <div class="mb-4 grid gap-4 lg:grid-cols-5">
        <!-- ranking de grupos -->
        <section class="rounded-xl border border-neutro-linha bg-white p-5 lg:col-span-3">
          <div class="mb-4 flex items-baseline justify-between">
            <h2 class="font-semibold">
              <template v-if="!grupoAberto">Para onde foi o dinheiro</template>
              <template v-else>
                <button class="text-neutro-texto hover:text-lojao" @click="grupoAberto = null">Grupos</button>
                <span class="text-neutro-texto"> › </span>{{ grupoAberto }}
              </template>
            </h2>
            <span class="text-xs text-neutro-texto">{{ grupoAberto ? 'clique em Grupos para voltar' : 'clique num grupo para abrir' }}</span>
          </div>

          <!-- nível 1: grupos -->
          <ul v-if="!grupoAberto" class="space-y-0.5">
            <li v-for="g in gruposMes" :key="g.nome">
              <button
                class="group grid w-full grid-cols-[11rem_1fr_6.5rem] items-center gap-3 rounded-md px-1 py-1.5 text-left text-sm hover:bg-slate-50"
                @click="grupoAberto = g.nome"
                @mousemove="mostrarDica($event, g.nome, [brl.format(g.total), `${pct(g.total, kpi.total)} do mês`])"
                @mouseleave="dica = null"
              >
                <span class="truncate font-medium" :class="g.nome === SEM_CLASSIFICACAO ? 'text-amber-800' : ''">{{ g.nome }}</span>
                <span class="h-5">
                  <span
                    class="block h-full rounded-r transition-all group-hover:brightness-90"
                    :class="g.nome === SEM_CLASSIFICACAO ? 'bg-amber-400' : 'bg-[#2a78d6]'"
                    :style="{ width: `${Math.max((g.total / maiorGrupo) * 100, 0.5)}%` }"
                  />
                </span>
                <span class="text-right tabular-nums">{{ compacto(g.total) }}</span>
              </button>
            </li>
          </ul>

          <!-- nível 2: categorias do grupo -->
          <ul v-else class="space-y-2">
            <li v-for="c in categoriasGrupo" :key="c.nome">
              <div
                class="grid grid-cols-[11rem_1fr_6.5rem] items-center gap-3 px-1 text-sm"
                @mousemove="mostrarDica($event, c.nome, [brl.format(c.total), `${pct(c.total, totalGrupoAberto)} do grupo`])"
                @mouseleave="dica = null"
              >
                <span class="truncate font-medium">{{ c.nome }}</span>
                <span class="h-5"><span class="block h-full rounded-r bg-[#2a78d6]" :style="{ width: `${Math.max((c.total / (categoriasGrupo[0]?.total || 1)) * 100, 0.5)}%` }" /></span>
                <span class="text-right tabular-nums">{{ compacto(c.total) }}</span>
              </div>
              <ul v-if="c.subs.length > 1" class="mt-1 space-y-0.5 pl-4">
                <li v-for="s in c.subs" :key="s.nome" class="grid grid-cols-[10rem_1fr_6.5rem] items-center gap-3 px-1 text-xs text-neutro-texto">
                  <span class="truncate">{{ s.nome }}</span>
                  <span class="h-2"><span class="block h-full rounded-r bg-[#9ec5f4]" :style="{ width: `${Math.max((s.total / c.total) * 100, 0.5)}%` }" /></span>
                  <span class="text-right tabular-nums">{{ compacto(s.total) }}</span>
                </li>
              </ul>
            </li>
          </ul>
        </section>

        <!-- evolução mensal -->
        <section class="flex flex-col rounded-xl border border-neutro-linha bg-white p-5 lg:col-span-2">
          <div class="mb-4 flex items-baseline justify-between">
            <h2 class="font-semibold">Mês a mês<span v-if="grupoAberto" class="font-normal text-neutro-texto"> · {{ grupoAberto }}</span></h2>
            <span class="text-xs text-neutro-texto">clique num mês</span>
          </div>
          <div class="flex min-h-56 flex-1 items-end gap-1.5 border-b border-neutro-linha">
            <button
              v-for="e in evolucao"
              :key="e.mes"
              class="group relative flex h-full flex-1 flex-col items-center justify-end"
              @click="mesSelecionado = e.mes"
              @mousemove="mostrarDica($event, nomeMes(e.mes, 'longo'), [brl.format(e.total)])"
              @mouseleave="dica = null"
            >
              <span v-if="e.mes === mesSelecionado" class="mb-1 whitespace-nowrap text-xs font-semibold tabular-nums">{{ compacto(e.total) }}</span>
              <span
                class="block w-full max-w-12 rounded-t transition-all"
                :class="e.mes === mesSelecionado ? 'bg-[#2a78d6]' : 'bg-slate-300 group-hover:bg-slate-400'"
                :style="{ height: `${Math.max((e.total / maxEvolucao) * 85, 0.5)}%` }"
              />
            </button>
          </div>
          <div class="mt-1.5 flex gap-1.5">
            <span v-for="e in evolucao" :key="e.mes" class="flex-1 text-center text-xs" :class="e.mes === mesSelecionado ? 'font-semibold' : 'text-neutro-texto'">
              {{ nomeMes(e.mes) }}
            </span>
          </div>
        </section>
      </div>

      <!-- tabela no formato da planilha -->
      <section class="overflow-hidden rounded-xl border border-neutro-linha bg-white">
        <div class="flex items-baseline justify-between px-5 py-4">
          <h2 class="font-semibold">Despesas mensais</h2>
          <span class="text-xs text-neutro-texto">clique num grupo para ver as categorias</span>
        </div>
        <div class="overflow-x-auto">
          <table class="w-full text-sm tabular-nums">
            <thead class="bg-slate-50 text-xs uppercase tracking-wide text-neutro-texto">
              <tr>
                <th class="sticky left-0 bg-slate-50 px-5 py-2.5 text-left font-medium">Grupo / categoria</th>
                <th
                  v-for="m in meses"
                  :key="m"
                  class="px-3 py-2.5 text-right font-medium"
                  :class="m === mesSelecionado ? 'text-grafite' : ''"
                >
                  {{ nomeMes(m) }}
                </th>
                <th class="px-5 py-2.5 text-right font-medium">Total</th>
              </tr>
            </thead>
            <tbody>
              <template v-for="g in tabela" :key="g.nome">
                <tr class="cursor-pointer border-t border-neutro-linha hover:bg-slate-50" @click="alternar(g.nome)">
                  <td class="sticky left-0 bg-white px-5 py-2 font-semibold" :class="g.nome === SEM_CLASSIFICACAO ? 'text-amber-800' : ''">
                    <span class="inline-block w-4 text-neutro-texto">{{ expandidos.has(g.nome) ? '▾' : '▸' }}</span>{{ g.nome }}
                  </td>
                  <td v-for="(v, i) in g.valores" :key="i" class="px-3 py-2 text-right" :class="meses[i] === mesSelecionado ? 'bg-[#cde2fb]/40 font-semibold' : ''">
                    {{ v ? compacto(v) : '—' }}
                  </td>
                  <td class="px-5 py-2 text-right font-semibold">{{ compacto(g.total) }}</td>
                </tr>
                <template v-if="expandidos.has(g.nome)">
                  <tr v-for="c in g.cats" :key="c.nome" class="text-neutro-texto">
                    <td class="sticky left-0 bg-white py-1.5 pl-11 pr-5">{{ c.nome }}</td>
                    <td v-for="(v, i) in c.valores" :key="i" class="px-3 py-1.5 text-right" :class="meses[i] === mesSelecionado ? 'bg-[#cde2fb]/40' : ''">
                      {{ v ? compacto(v) : '—' }}
                    </td>
                    <td class="px-5 py-1.5 text-right">{{ compacto(c.total) }}</td>
                  </tr>
                </template>
              </template>
            </tbody>
            <tfoot>
              <tr class="border-t-2 border-grafite/20 font-semibold">
                <td class="sticky left-0 bg-white px-5 py-2.5">TOTAL MENSAL</td>
                <td v-for="(v, i) in totaisTabela" :key="i" class="px-3 py-2.5 text-right" :class="meses[i] === mesSelecionado ? 'bg-[#cde2fb]/40' : ''">
                  {{ compacto(v) }}
                </td>
                <td class="px-5 py-2.5 text-right">{{ compacto(totaisTabela.reduce((a, b) => a + b, 0)) }}</td>
              </tr>
            </tfoot>
          </table>
        </div>
      </section>
    </template>

    <!-- tooltip -->
    <div
      v-if="dica"
      class="pointer-events-none fixed z-50 rounded-lg bg-grafite px-3 py-2 text-xs text-white shadow-lg"
      :style="{ left: `${dica.x + 14}px`, top: `${dica.y + 14}px` }"
    >
      <div class="font-semibold">{{ dica.titulo }}</div>
      <div v-for="(t, i) in dica.linhas" :key="i" class="tabular-nums text-white/80">{{ t }}</div>
    </div>
  </div>
</template>
