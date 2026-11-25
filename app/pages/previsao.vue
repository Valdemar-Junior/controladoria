<script setup lang="ts">
useHead({ title: 'Previsão de pagamentos · Controladoria Lojão' })

type Situacao = 'pago' | 'pago_antes' | 'a_pagar' | 'cancelado' | 'adiado' | 'imprevisto' | 'veio_adiado' | 'sem_foto'
interface Linha {
  semana: string
  data_ref: string
  situacao: Situacao
  projecao: boolean
  foto_semana: string | null
  titulo_id: number
  numero_titulo: number | null
  filial_id: number | null
  historico_id: number | null
  historico_erp: string
  grupo: string | null
  categoria: string | null
  subcategoria: string | null
  fornecedor_nome: string | null
  venc_foto: string | null
  venc_atual: string | null
  valor_foto: number | null
  valor_atual: number
  valor_pago: number
  valor_pendente: number
  data_pagamento: string | null
}

const supabase = useSupabaseClient()
const FILIAIS: Record<number, string> = { 5: 'Assú', 6: 'Depósito', 9: 'Mossoró' }
const NA_SEMANA: Situacao[] = ['pago', 'pago_antes', 'a_pagar', 'imprevisto', 'veio_adiado', 'sem_foto'] // conta como "desta semana" hoje
const PREVISTO: Situacao[] = ['pago', 'pago_antes', 'a_pagar', 'cancelado', 'adiado'] // estava na foto desta semana
const COMPARAVEL: Situacao[] = ['pago', 'pago_antes', 'a_pagar'] // na foto e ainda nesta semana: dá para medir diferença

// ---------- datas (sempre 'AAAA-MM-DD', sem fuso) ----------
const pad = (n: number) => String(n).padStart(2, '0')
const iso = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
function parse(s: string) { const [a, m, d] = s.split('-').map(Number); return new Date(a!, m! - 1, d!) }
function addDias(s: string, n: number) { const d = parse(s); d.setDate(d.getDate() + n); return iso(d) }
function segundaDe(s: string) { const d = parse(s); d.setDate(d.getDate() - ((d.getDay() + 6) % 7)); return iso(d) }
function dataPrevista(s: string) { const dia = parse(s).getDay(); return dia === 6 ? addDias(s, 2) : dia === 0 ? addDias(s, 1) : s }
function diaCurto(s: string) { return parse(s).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' }) }
function diaSemana(s: string) { return parse(s).toLocaleDateString('pt-BR', { weekday: 'short' }).replace('.', '') }
function nomeMes(mes: string) {
  const t = parse(`${mes}-01`).toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' })
  return t.charAt(0).toUpperCase() + t.slice(1)
}

// ---------- números ----------
const brl = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })
function compacto(v: number) {
  const a = Math.abs(v)
  if (a >= 1e6) return `R$ ${(v / 1e6).toLocaleString('pt-BR', { maximumFractionDigits: 2 })} mi`
  if (a >= 1e4) return `R$ ${(v / 1e3).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} mil`
  return brl.format(v)
}
const pctTxt = (v: number) => `${(v * 100).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`
const soma = <T,>(l: T[], f: (x: T) => number) => l.reduce((s, x) => s + f(x), 0)

// ---------- período ----------
const hoje = iso(new Date())
const modo = ref<'semana' | 'mes'>('semana')
const semana = ref(segundaDe(dataPrevista(hoje))) // segunda-feira
const mes = ref(dataPrevista(hoje).slice(0, 7))

const periodo = computed(() => {
  if (modo.value === 'semana') return { de: semana.value, ate: addDias(semana.value, 4) }
  const ini = `${mes.value}-01`
  const fim = parse(ini); fim.setMonth(fim.getMonth() + 1); fim.setDate(0)
  return { de: ini, ate: iso(fim) }
})
const rotuloPeriodo = computed(() => modo.value === 'semana'
  ? `seg ${diaCurto(periodo.value.de)} → sex ${diaCurto(periodo.value.ate)}`
  : nomeMes(mes.value))

function andar(passo: number) {
  if (modo.value === 'semana') semana.value = addDias(semana.value, 7 * passo)
  else { const d = parse(`${mes.value}-01`); d.setMonth(d.getMonth() + passo); mes.value = iso(d).slice(0, 7) }
}
function voltarParaHoje() { semana.value = segundaDe(dataPrevista(hoje)); mes.value = dataPrevista(hoje).slice(0, 7) }
function abrirSemana(s: string) { semana.value = s; modo.value = 'semana' }

// ---------- carregar ----------
const linhas = ref<Linha[]>([])
const carregando = ref(true)
const erro = ref('')
const fotos = ref<{ semana_inicio: string, tirada_em: string }[]>([])

async function carregar() {
  carregando.value = true
  erro.value = ''
  const todas: Linha[] = []
  for (let de = 0; ; de += 1000) {
    const { data, error } = await supabase
      .rpc('previsao_titulos', { p_de: periodo.value.de, p_ate: periodo.value.ate })
      .range(de, de + 999)
    if (error) {
      erro.value = error.message.includes('previsao_titulos')
        ? 'A previsão ainda não existe no Supabase. Rode a migration 20261118000400_previsao_pagamentos.sql.'
        : `Não foi possível carregar: ${error.message}`
      break
    }
    todas.push(...(data as Linha[]).map((l) => {
      const pago = Number(l.valor_pago ?? 0)
      const pendente = Number(l.valor_pendente ?? 0)
      // título ainda em aberto: "hoje" = o que já foi pago + o que falta (abatimento conta como desconto)
      const emAberto = NA_SEMANA.includes(l.situacao) && pendente > 0
      return {
        ...l,
        valor_foto: l.valor_foto === null ? null : Number(l.valor_foto),
        valor_atual: emAberto ? pago + pendente : Number(l.valor_atual),
        valor_pago: pago,
        valor_pendente: pendente,
      }
    }))
    if (data.length < 1000) break
  }
  linhas.value = todas
  const { data: f } = await supabase.from('fotos').select('semana_inicio, tirada_em').order('semana_inicio', { ascending: false }).limit(20)
  fotos.value = f ?? []
  carregando.value = false
}
watch(periodo, carregar, { immediate: true })

// ---------- filtros ----------
const filial = ref(0)
const base = computed(() => linhas.value.filter(l => !filial.value || l.filial_id === filial.value))

// ---------- regras ----------
const diferenca = (l: Linha) => COMPARAVEL.includes(l.situacao) && l.valor_foto !== null ? l.valor_atual - l.valor_foto : 0
const quitado = (l: Linha) => l.valor_pago > 0 && l.valor_pendente <= 0

function resumo(lista: Linha[]) {
  const previstos = lista.filter(l => PREVISTO.includes(l.situacao))
  const naSemana = lista.filter(l => NA_SEMANA.includes(l.situacao))
  const imprev = lista.filter(l => l.situacao === 'imprevisto')
  const com = lista.filter(l => Math.abs(diferenca(l)) >= 0.01)
  const r = {
    previsto: soma(previstos, l => l.valor_foto ?? 0),
    qtdPrevisto: previstos.length,
    pago: soma(naSemana, l => l.valor_pago),
    qtdPago: naSemana.filter(quitado).length,
    aPagar: soma(naSemana, l => l.valor_pendente),
    qtdAPagar: naSemana.filter(l => l.valor_pendente > 0).length,
    imprevistos: soma(imprev, l => l.valor_atual),
    qtdImprevistos: imprev.length,
    acrescimos: soma(com.filter(l => diferenca(l) > 0), diferenca),
    descontos: soma(com.filter(l => diferenca(l) < 0), diferenca),
    qtdDiferenca: com.length,
    adiados: soma(lista.filter(l => l.situacao === 'adiado'), l => l.valor_foto ?? 0),
    cancelados: soma(lista.filter(l => l.situacao === 'cancelado'), l => l.valor_foto ?? 0),
    vieram: soma(lista.filter(l => l.situacao === 'veio_adiado'), l => l.valor_atual),
    semFoto: soma(lista.filter(l => l.situacao === 'sem_foto'), l => l.valor_atual),
  }
  // conferência: previsto − saíram + entraram ± diferenças = pago + a pagar
  const esperado = r.previsto - r.adiados - r.cancelados + r.vieram + r.imprevistos + r.semFoto + r.acrescimos + r.descontos
  return { ...r, esperado, fecha: Math.abs(esperado - (r.pago + r.aPagar)) < 0.05 }
}
const total = computed(() => resumo(base.value))

const situacaoFoto = computed(() => {
  const ls = base.value
  if (!ls.length) return null
  if (ls.every(l => !l.foto_semana)) return { tipo: 'sem' as const }
  const proj = ls.find(l => l.projecao && l.foto_semana)
  if (modo.value === 'semana' && proj) return { tipo: 'projecao' as const, foto: proj.foto_semana! }
  const propria = fotos.value.find(f => f.semana_inicio === semana.value)
  if (modo.value === 'semana' && propria) return { tipo: 'propria' as const, em: propria.tirada_em }
  return null
})

// ---------- semana: dia a dia ----------
const dias = computed(() => Array.from({ length: 5 }, (_, i) => addDias(semana.value, i)).map((d) => {
  const doDia = base.value.filter(l => l.data_ref === d)
  return {
    dia: d,
    previsto: soma(doDia.filter(l => PREVISTO.includes(l.situacao)), l => l.valor_foto ?? 0),
    pago: soma(doDia.filter(l => NA_SEMANA.includes(l.situacao)), l => l.valor_pago),
    aPagar: soma(doDia.filter(l => NA_SEMANA.includes(l.situacao)), l => l.valor_pendente),
  }
}))
const maxDia = computed(() => Math.max(1, ...dias.value.flatMap(d => [d.previsto, d.pago + d.aPagar])))

// ---------- mês: semana a semana ----------
const semanasMes = computed(() => {
  const porSemana = new Map<string, Linha[]>()
  for (const l of base.value) porSemana.set(l.semana, [...(porSemana.get(l.semana) ?? []), l])
  return [...porSemana.keys()].sort().map((s) => {
    const ls = porSemana.get(s)!
    const r = resumo(ls)
    const de = s < periodo.value.de ? periodo.value.de : s
    const ate = addDias(s, 4) > periodo.value.ate ? periodo.value.ate : addDias(s, 4)
    const foto = ls.find(l => l.foto_semana)
    return { semana: s, de, ate, cortada: de !== s || ate !== addDias(s, 4), r, foto: foto ? (foto.projecao ? 'projecao' : 'propria') : 'sem' }
  })
})

// ---------- por grupo ----------
const porGrupo = computed(() => {
  const m = new Map<string, Linha[]>()
  for (const l of base.value) {
    const g = l.grupo ?? 'SEM CLASSIFICAÇÃO'
    m.set(g, [...(m.get(g) ?? []), l])
  }
  return [...m].map(([nome, ls]) => ({ nome, r: resumo(ls) }))
    .sort((a, b) => (b.r.pago + b.r.aPagar) - (a.r.pago + a.r.aPagar))
})

// ---------- títulos ----------
const ABAS = [
  { id: 'todos', rotulo: 'Todos' },
  { id: 'a_pagar', rotulo: 'A pagar' },
  { id: 'pagos', rotulo: 'Pagos' },
  { id: 'imprevistos', rotulo: 'Imprevistos' },
  { id: 'diferenca', rotulo: 'Com diferença' },
  { id: 'mudaram', rotulo: 'Adiados e cancelados' },
] as const
const aba = ref<typeof ABAS[number]['id']>('todos')
const busca = ref('')
const aberto = ref<string | null>(null)
const limite = ref(200)

function normalizar(s: string) { return s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase() }
const titulos = computed(() => {
  const termo = normalizar(busca.value.trim())
  return base.value.filter((l) => {
    const ok = {
      todos: true,
      a_pagar: NA_SEMANA.includes(l.situacao) && l.valor_pendente > 0,
      pagos: NA_SEMANA.includes(l.situacao) && quitado(l),
      imprevistos: l.situacao === 'imprevisto',
      diferenca: Math.abs(diferenca(l)) >= 0.01,
      mudaram: ['adiado', 'cancelado', 'veio_adiado'].includes(l.situacao),
    }[aba.value]
    if (!ok) return false
    if (!termo) return true
    return normalizar([l.fornecedor_nome, l.historico_erp, l.grupo, l.categoria, l.numero_titulo].join(' ')).includes(termo)
  })
})
watch([aba, busca, periodo, filial], () => { limite.value = 200; aberto.value = null })

const SITUACAO: Record<Situacao, { rotulo: string, classe: string }> = {
  pago: { rotulo: '✓ Pago', classe: 'bg-emerald-50 text-emerald-800 ring-emerald-200' },
  pago_antes: { rotulo: '✓ Pago antes da foto', classe: 'bg-emerald-50 text-emerald-800 ring-emerald-200' },
  a_pagar: { rotulo: '⏳ A pagar', classe: 'bg-slate-100 text-slate-700 ring-slate-200' },
  imprevisto: { rotulo: '● Imprevisto', classe: 'bg-lojao-claro text-lojao-escuro ring-red-200' },
  adiado: { rotulo: '→ Adiado', classe: 'bg-orange-50 text-orange-800 ring-orange-200' },
  veio_adiado: { rotulo: '← Veio adiado', classe: 'bg-orange-50 text-orange-800 ring-orange-200' },
  cancelado: { rotulo: '✕ Cancelado', classe: 'bg-slate-100 text-slate-500 ring-slate-200' },
  sem_foto: { rotulo: 'Sem foto', classe: 'bg-slate-100 text-slate-500 ring-slate-200' },
}
function rotuloSituacao(l: Linha) {
  if (l.situacao === 'adiado' && l.venc_atual && l.venc_foto && l.venc_atual < l.venc_foto) return '← Antecipado'
  if (l.situacao === 'a_pagar' && l.valor_pago > 0) return '⏳ Pago em parte'
  return SITUACAO[l.situacao].rotulo
}
</script>

<template>
  <div class="mx-auto max-w-7xl">
    <!-- título + período -->
    <div class="mb-5 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 class="text-2xl font-semibold">Previsão de pagamentos</h1>
        <p class="mt-1 max-w-3xl text-sm text-neutro-texto">
          Todo sábado às 23h a gente tira uma foto do que tem para pagar. Aqui você vê o que estava previsto, o que já foi pago,
          o que apareceu depois e o que mudou de valor. Vencimento no sábado ou domingo conta na segunda.
        </p>
      </div>
    </div>

    <div class="mb-4 flex flex-wrap items-center gap-2 text-sm">
      <div class="flex rounded-lg border border-neutro-linha bg-white p-0.5">
        <button
          v-for="m in (['semana', 'mes'] as const)"
          :key="m"
          class="rounded-md px-3 py-1.5 font-medium"
          :class="modo === m ? 'bg-lojao-claro text-lojao-escuro' : 'text-neutro-texto hover:text-grafite'"
          @click="modo = m"
        >
          {{ m === 'semana' ? 'Semana' : 'Mês' }}
        </button>
      </div>
      <div class="flex items-center rounded-lg border border-neutro-linha bg-white">
        <button class="px-3 py-2 text-neutro-texto hover:text-grafite" aria-label="Anterior" @click="andar(-1)">‹</button>
        <span class="min-w-48 text-center font-semibold">{{ rotuloPeriodo }}</span>
        <button class="px-3 py-2 text-neutro-texto hover:text-grafite" aria-label="Próximo" @click="andar(1)">›</button>
      </div>
      <button class="rounded-lg px-3 py-2 font-medium text-neutro-texto hover:bg-white hover:text-grafite" @click="voltarParaHoje">Hoje</button>
      <div class="ml-auto flex rounded-lg border border-neutro-linha bg-white p-0.5">
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
    </div>

    <p v-if="erro" class="mb-4 rounded-lg bg-lojao-claro px-4 py-3 text-sm text-lojao-escuro">{{ erro }}</p>
    <div v-if="carregando" class="rounded-xl border border-neutro-linha bg-white px-4 py-16 text-center text-neutro-texto">Carregando…</div>

    <template v-else-if="!erro">
      <!-- de onde vem a previsão -->
      <div
        v-if="situacaoFoto?.tipo === 'sem'"
        class="mb-4 rounded-xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-700"
      >
        <strong>Sem foto para este período.</strong> A primeira foto é tirada no sábado às 23h; antes dela só dá para ver o que foi pago e o que está em aberto, sem comparar com a previsão.
      </div>
      <div
        v-else-if="situacaoFoto?.tipo === 'projecao'"
        class="mb-4 rounded-xl border border-sky-200 bg-sky-50 px-4 py-3 text-sm text-sky-900"
      >
        <strong>Previsão.</strong> Esta semana ainda não tem foto própria; os números usam a foto de {{ diaCurto(situacaoFoto.foto) }} (sábado anterior a ela).
      </div>
      <p v-else-if="situacaoFoto?.tipo === 'propria'" class="mb-4 text-xs text-neutro-texto">
        Foto tirada em {{ new Date(situacaoFoto.em).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' }) }}.
      </p>

      <!-- cards -->
      <div class="mb-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
        <div class="rounded-xl border border-neutro-linha bg-white p-4">
          <div class="text-xs font-medium uppercase tracking-wide text-neutro-texto">Previsto na foto</div>
          <div class="mt-1 text-2xl font-semibold tabular-nums">{{ compacto(total.previsto) }}</div>
          <div class="mt-1 text-xs text-neutro-texto">{{ total.qtdPrevisto }} títulos</div>
        </div>
        <div class="rounded-xl border border-neutro-linha bg-white p-4">
          <div class="text-xs font-medium uppercase tracking-wide text-neutro-texto">Pago</div>
          <div class="mt-1 text-2xl font-semibold tabular-nums">{{ compacto(total.pago) }}</div>
          <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-slate-100">
            <div class="h-full rounded-full bg-[#2a78d6]" :style="{ width: `${Math.min(100, (total.pago / Math.max(total.pago + total.aPagar, 1)) * 100)}%` }" />
          </div>
          <div class="mt-1 text-xs text-neutro-texto">{{ total.qtdPago }} títulos · {{ pctTxt(total.pago / Math.max(total.pago + total.aPagar, 1)) }} da semana</div>
        </div>
        <button
          class="rounded-xl border bg-white p-4 text-left hover:border-lojao"
          :class="total.qtdImprevistos ? 'border-red-200' : 'border-neutro-linha'"
          @click="aba = 'imprevistos'"
        >
          <div class="text-xs font-medium uppercase tracking-wide text-neutro-texto">Imprevistos</div>
          <div class="mt-1 text-2xl font-semibold tabular-nums" :class="total.qtdImprevistos ? 'text-lojao-escuro' : ''">{{ compacto(total.imprevistos) }}</div>
          <div class="mt-1 text-xs text-neutro-texto">{{ total.qtdImprevistos }} títulos que não estavam na foto</div>
        </button>
        <button class="rounded-xl border border-neutro-linha bg-white p-4 text-left hover:border-lojao" @click="aba = 'diferenca'">
          <div class="text-xs font-medium uppercase tracking-wide text-neutro-texto">Acréscimos e descontos</div>
          <div class="mt-1 text-2xl font-semibold tabular-nums">
            <span v-if="!total.qtdDiferenca">—</span>
            <template v-else>{{ total.acrescimos + total.descontos >= 0 ? '▲' : '▼' }} {{ compacto(Math.abs(total.acrescimos + total.descontos)) }}</template>
          </div>
          <div class="mt-1 text-xs text-neutro-texto">
            <template v-if="total.qtdDiferenca">
              {{ total.qtdDiferenca }} títulos ·
              <span v-if="total.acrescimos">▲ {{ compacto(total.acrescimos) }}</span>
              <span v-if="total.acrescimos && total.descontos"> · </span>
              <span v-if="total.descontos">▼ {{ compacto(Math.abs(total.descontos)) }}</span>
            </template>
            <template v-else>nenhum título mudou de valor</template>
          </div>
        </button>
        <div class="rounded-xl border border-neutro-linha bg-white p-4">
          <div class="text-xs font-medium uppercase tracking-wide text-neutro-texto">A pagar</div>
          <div class="mt-1 text-2xl font-semibold tabular-nums">{{ compacto(total.aPagar) }}</div>
          <div class="mt-1 text-xs text-neutro-texto">{{ total.qtdAPagar }} títulos em aberto</div>
        </div>
      </div>

      <!-- conferência -->
      <p v-if="total.qtdPrevisto" class="mb-4 text-xs text-neutro-texto">
        Previsto {{ compacto(total.previsto) }}
        <template v-if="total.adiados"> − adiados {{ compacto(total.adiados) }}</template>
        <template v-if="total.cancelados"> − cancelados {{ compacto(total.cancelados) }}</template>
        <template v-if="total.vieram"> + vieram adiados {{ compacto(total.vieram) }}</template>
        <template v-if="total.imprevistos"> + imprevistos {{ compacto(total.imprevistos) }}</template>
        <template v-if="total.acrescimos + total.descontos"> {{ total.acrescimos + total.descontos > 0 ? '+' : '−' }} diferenças {{ compacto(Math.abs(total.acrescimos + total.descontos)) }}</template>
        = <strong class="text-grafite">{{ compacto(total.esperado) }}</strong>
        <span :class="total.fecha ? 'text-emerald-700' : 'text-lojao-escuro'">
          {{ total.fecha ? '✓ bate com pago + a pagar' : `≠ pago + a pagar (${compacto(total.pago + total.aPagar)})` }}
        </span>
      </p>

      <div class="mb-4 grid gap-4 lg:grid-cols-5">
        <!-- semana: dia a dia -->
        <section v-if="modo === 'semana'" class="rounded-xl border border-neutro-linha bg-white p-5 lg:col-span-3">
          <div class="mb-4 flex flex-wrap items-baseline justify-between gap-2">
            <h2 class="font-semibold">Dia a dia</h2>
            <div class="flex gap-4 text-xs text-neutro-texto">
              <span class="flex items-center gap-1.5"><span class="h-2.5 w-2.5 rounded-sm bg-slate-300" />Previsto na foto</span>
              <span class="flex items-center gap-1.5"><span class="h-2.5 w-2.5 rounded-sm bg-[#2a78d6]" />Pago</span>
              <span class="flex items-center gap-1.5"><span class="h-2.5 w-2.5 rounded-sm bg-[#b7d3f6]" />A pagar</span>
            </div>
          </div>
          <div class="grid grid-cols-5 gap-3">
            <div v-for="d in dias" :key="d.dia" class="flex flex-col">
              <div class="flex h-48 items-end justify-center gap-1 border-b border-neutro-linha">
                <span class="w-1/3 max-w-8 rounded-t bg-slate-300" :style="{ height: `${(d.previsto / maxDia) * 100}%` }" :title="`Previsto: ${brl.format(d.previsto)}`" />
                <span class="flex w-1/3 max-w-8 flex-col justify-end" :style="{ height: `${((d.pago + d.aPagar) / maxDia) * 100}%` }">
                  <span class="block rounded-t bg-[#b7d3f6]" :style="{ height: `${(d.aPagar / Math.max(d.pago + d.aPagar, 1)) * 100}%` }" :title="`A pagar: ${brl.format(d.aPagar)}`" />
                  <span class="block bg-[#2a78d6]" :class="d.aPagar ? 'mt-0.5' : 'rounded-t'" :style="{ height: `${(d.pago / Math.max(d.pago + d.aPagar, 1)) * 100}%` }" :title="`Pago: ${brl.format(d.pago)}`" />
                </span>
              </div>
              <div class="mt-2 text-center text-xs">
                <div class="font-semibold" :class="d.dia === hoje ? 'text-lojao' : ''">{{ diaSemana(d.dia) }} {{ diaCurto(d.dia) }}</div>
                <div class="tabular-nums text-neutro-texto">{{ compacto(d.pago + d.aPagar) }}</div>
                <div v-if="d.dia === semana" class="text-[11px] text-neutro-texto">+ sáb e dom</div>
              </div>
            </div>
          </div>
        </section>

        <!-- mês: semana a semana -->
        <section v-else class="overflow-hidden rounded-xl border border-neutro-linha bg-white lg:col-span-3">
          <h2 class="px-5 pb-2 pt-5 font-semibold">Semana a semana</h2>
          <table class="w-full text-sm tabular-nums">
            <thead class="bg-slate-50 text-xs uppercase tracking-wide text-neutro-texto">
              <tr>
                <th class="px-5 py-2 text-left font-medium">Semana</th>
                <th class="px-3 py-2 text-right font-medium">Previsto</th>
                <th class="px-3 py-2 text-right font-medium">Pago</th>
                <th class="px-3 py-2 text-right font-medium">Imprevistos</th>
                <th class="px-5 py-2 text-right font-medium">A pagar</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-neutro-linha">
              <tr v-for="s in semanasMes" :key="s.semana" class="cursor-pointer hover:bg-slate-50" @click="abrirSemana(s.semana)">
                <td class="px-5 py-2.5">
                  <div class="font-medium">{{ diaCurto(s.de) }} → {{ diaCurto(s.ate) }}</div>
                  <div class="text-xs text-neutro-texto">
                    {{ s.foto === 'propria' ? 'com foto' : s.foto === 'projecao' ? 'previsão' : 'sem foto' }}<span v-if="s.cortada"> · semana cortada no mês</span>
                  </div>
                </td>
                <td class="px-3 py-2.5 text-right">{{ s.r.qtdPrevisto ? compacto(s.r.previsto) : '—' }}</td>
                <td class="px-3 py-2.5 text-right">{{ compacto(s.r.pago) }}</td>
                <td class="px-3 py-2.5 text-right" :class="s.r.qtdImprevistos ? 'text-lojao-escuro' : 'text-neutro-texto'">{{ s.r.qtdImprevistos ? compacto(s.r.imprevistos) : '—' }}</td>
                <td class="px-5 py-2.5 text-right">{{ compacto(s.r.aPagar) }}</td>
              </tr>
            </tbody>
          </table>
        </section>

        <!-- por grupo -->
        <section class="overflow-hidden rounded-xl border border-neutro-linha bg-white lg:col-span-2">
          <h2 class="px-5 pb-2 pt-5 font-semibold">Por grupo</h2>
          <table class="w-full text-sm tabular-nums">
            <thead class="bg-slate-50 text-xs uppercase tracking-wide text-neutro-texto">
              <tr>
                <th class="px-5 py-2 text-left font-medium">Grupo</th>
                <th class="px-3 py-2 text-right font-medium">Previsto</th>
                <th class="px-5 py-2 text-right font-medium">Hoje</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-neutro-linha">
              <tr v-for="g in porGrupo" :key="g.nome">
                <td class="px-5 py-2" :class="g.nome === 'SEM CLASSIFICAÇÃO' ? 'text-amber-800' : ''">
                  <div class="truncate font-medium">{{ g.nome }}</div>
                  <div v-if="g.r.qtdImprevistos" class="text-xs text-lojao-escuro">{{ g.r.qtdImprevistos }} imprevisto(s) · {{ compacto(g.r.imprevistos) }}</div>
                </td>
                <td class="px-3 py-2 text-right text-neutro-texto">{{ g.r.qtdPrevisto ? compacto(g.r.previsto) : '—' }}</td>
                <td class="px-5 py-2 text-right font-medium">{{ compacto(g.r.pago + g.r.aPagar) }}</td>
              </tr>
            </tbody>
          </table>
        </section>
      </div>

      <!-- títulos -->
      <section class="overflow-hidden rounded-xl border border-neutro-linha bg-white">
        <div class="flex flex-wrap items-center gap-3 px-5 py-4">
          <h2 class="mr-2 font-semibold">Títulos</h2>
          <div class="flex flex-wrap gap-1 text-sm">
            <button
              v-for="a in ABAS"
              :key="a.id"
              class="rounded-md px-2.5 py-1 font-medium"
              :class="aba === a.id ? 'bg-lojao-claro text-lojao-escuro' : 'text-neutro-texto hover:text-grafite'"
              @click="aba = a.id"
            >
              {{ a.rotulo }}
            </button>
          </div>
          <input
            v-model="busca"
            type="search"
            placeholder="Buscar fornecedor, histórico, nº…"
            class="ml-auto min-w-56 rounded-lg border border-neutro-linha px-3 py-1.5 text-sm outline-none focus:border-lojao"
          >
        </div>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead class="bg-slate-50 text-left text-xs uppercase tracking-wide text-neutro-texto">
              <tr>
                <th class="px-5 py-2 font-medium">Pagamento</th>
                <th class="px-3 py-2 font-medium">Fornecedor / histórico</th>
                <th class="px-3 py-2 font-medium">Classificação</th>
                <th class="px-3 py-2 text-right font-medium">Na foto</th>
                <th class="px-3 py-2 text-right font-medium">Hoje</th>
                <th class="px-5 py-2 font-medium">Situação</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-neutro-linha">
              <tr v-if="!titulos.length">
                <td colspan="6" class="px-5 py-10 text-center text-neutro-texto">Nenhum título aqui.</td>
              </tr>
              <template v-for="l in titulos.slice(0, limite)" :key="`${l.semana}-${l.titulo_id}-${l.situacao}`">
                <tr
                  class="cursor-pointer align-top hover:bg-slate-50"
                  :class="['cancelado', 'adiado'].includes(l.situacao) ? 'text-neutro-texto' : ''"
                  @click="aberto = aberto === `${l.semana}-${l.titulo_id}-${l.situacao}` ? null : `${l.semana}-${l.titulo_id}-${l.situacao}`"
                >
                  <td class="whitespace-nowrap px-5 py-2.5">
                    <div class="font-medium">{{ diaSemana(l.data_ref) }} {{ diaCurto(l.data_ref) }}</div>
                    <div v-if="(l.venc_foto ?? l.venc_atual) && (l.venc_foto ?? l.venc_atual) !== l.data_ref" class="text-xs text-neutro-texto">
                      venceu {{ diaSemana((l.venc_foto ?? l.venc_atual)!) }} {{ diaCurto((l.venc_foto ?? l.venc_atual)!) }}
                    </div>
                  </td>
                  <td class="px-3 py-2.5">
                    <div class="font-medium">{{ l.fornecedor_nome ?? '—' }}</div>
                    <div class="text-xs text-neutro-texto">{{ l.historico_erp }}<span v-if="l.filial_id && FILIAIS[l.filial_id]"> · {{ FILIAIS[l.filial_id] }}</span></div>
                  </td>
                  <td class="px-3 py-2.5 text-xs">
                    <template v-if="l.grupo">
                      <div class="font-semibold uppercase tracking-wide text-neutro-texto">{{ l.grupo }}</div>
                      <div>{{ l.categoria }}</div>
                    </template>
                    <span v-else class="text-amber-800">sem classificação</span>
                  </td>
                  <td class="whitespace-nowrap px-3 py-2.5 text-right tabular-nums">{{ l.valor_foto === null ? '—' : brl.format(l.valor_foto) }}</td>
                  <td class="whitespace-nowrap px-3 py-2.5 text-right tabular-nums">
                    {{ brl.format(l.valor_atual) }}
                    <div v-if="Math.abs(diferenca(l)) >= 0.01" class="text-xs font-semibold" :class="diferenca(l) > 0 ? 'text-lojao-escuro' : 'text-emerald-700'">
                      {{ diferenca(l) > 0 ? '▲' : '▼' }} {{ pctTxt(Math.abs(diferenca(l)) / (l.valor_foto || 1)) }} · {{ brl.format(Math.abs(diferenca(l))) }}
                    </div>
                  </td>
                  <td class="whitespace-nowrap px-5 py-2.5">
                    <span class="inline-flex rounded-full px-2 py-0.5 text-xs font-medium ring-1" :class="SITUACAO[l.situacao].classe">{{ rotuloSituacao(l) }}</span>
                  </td>
                </tr>
                <tr v-if="aberto === `${l.semana}-${l.titulo_id}-${l.situacao}`" class="bg-slate-50/70">
                  <td colspan="6" class="px-5 py-3">
                    <dl class="grid grid-cols-2 gap-x-8 gap-y-2 text-xs sm:grid-cols-4">
                      <div><dt class="text-neutro-texto">Nº do título</dt><dd class="font-medium">{{ l.numero_titulo ?? '—' }}</dd></div>
                      <div><dt class="text-neutro-texto">Vencimento na foto</dt><dd class="font-medium">{{ l.venc_foto ? diaCurto(l.venc_foto) : 'não estava na foto' }}</dd></div>
                      <div><dt class="text-neutro-texto">Vencimento hoje</dt><dd class="font-medium">{{ l.venc_atual ? diaCurto(l.venc_atual) : '—' }}</dd></div>
                      <div><dt class="text-neutro-texto">Pago em</dt><dd class="font-medium">{{ l.data_pagamento ? diaCurto(l.data_pagamento) : '—' }}</dd></div>
                      <div><dt class="text-neutro-texto">Valor pago</dt><dd class="font-medium tabular-nums">{{ brl.format(l.valor_pago) }}</dd></div>
                      <div><dt class="text-neutro-texto">Em aberto</dt><dd class="font-medium tabular-nums">{{ brl.format(l.valor_pendente) }}</dd></div>
                      <div><dt class="text-neutro-texto">Subcategoria</dt><dd class="font-medium">{{ l.subcategoria ?? '—' }}</dd></div>
                      <div><dt class="text-neutro-texto">Foto usada</dt><dd class="font-medium">{{ l.foto_semana ? `semana de ${diaCurto(l.foto_semana)}` : 'nenhuma' }}</dd></div>
                    </dl>
                  </td>
                </tr>
              </template>
            </tbody>
          </table>
        </div>
        <div v-if="titulos.length > limite" class="border-t border-neutro-linha px-5 py-3 text-center">
          <button class="text-sm font-medium text-lojao hover:text-lojao-escuro" @click="limite += 200">
            Mostrar mais ({{ titulos.length - limite }} restantes)
          </button>
        </div>
      </section>
    </template>
  </div>
</template>
