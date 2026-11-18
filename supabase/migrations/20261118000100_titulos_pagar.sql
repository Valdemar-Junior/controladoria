-- Cópia das contas a pagar do ERP Solidus (titulos, tipo_titulo_id 1 e 3).
-- Quem escreve aqui é só o n8n, chamando a função sincronizar_titulos (no fim deste arquivo). Usuário logado só lê.

create table if not exists public.titulos_pagar (
  id                     integer primary key,      -- titulos.id no ERP
  empresa_id             integer,
  filial_id              integer,                  -- 5 Assú, 6 Depósito, 9 Mossoró
  tipo_titulo_id         integer,
  fornecedor_id          integer,                  -- titulos.pessoa_cliente_fornecedor_id
  historico_id           integer,                  -- titulos.historico_receita_despesa_id
  numero_titulo          bigint,
  data_emissao           date,
  data_vencimento        date not null,
  data_ultimo_pagamento  date,
  data_cancelamento      date,
  valor_nominal          numeric(14, 2) not null default 0,
  valor_pago             numeric(14, 2) not null default 0,
  valor_pendente         numeric(14, 2) not null default 0,
  observacao             text,
  erp_updated_at         timestamp,
  sincronizado_em        timestamptz not null default now()
);

create index if not exists titulos_pagar_vencimento_idx on public.titulos_pagar (data_vencimento);
create index if not exists titulos_pagar_historico_idx  on public.titulos_pagar (historico_id);

alter table public.titulos_pagar enable row level security;
drop policy if exists "logados leem" on public.titulos_pagar;
create policy "logados leem" on public.titulos_pagar for select to authenticated using (true);

-- Registro de cada sincronização (a tela mostra "atualizado em …")
create table if not exists public.sincronizacoes (
  id             bigint generated always as identity primary key,
  iniciado_em    timestamptz not null default now(),
  finalizado_em  timestamptz,
  desde          date,
  linhas         integer,
  erro           text
);
alter table public.sincronizacoes enable row level security;
drop policy if exists "logados leem" on public.sincronizacoes;
create policy "logados leem" on public.sincronizacoes for select to authenticated using (true);

-- Despesas por mês (vencimento), filial e classificação do financeiro.
-- Mesma ótica da planilha: soma do valor_nominal, por data de vencimento, sem cancelados.
create or replace view public.vw_despesas_mensais
with (security_invoker = true) as
select
  date_trunc('month', t.data_vencimento)::date      as mes,
  t.filial_id,
  t.historico_id,
  coalesce(d.historico_erp, 'Histórico ' || t.historico_id) as historico_erp,
  coalesce(d.situacao, 'pendente')                  as situacao,
  d.grupo,
  d.categoria,
  d.subcategoria,
  count(*)::int                                     as qtd,
  sum(t.valor_nominal)::numeric(14, 2)              as total,
  sum(t.valor_pago)::numeric(14, 2)                 as pago
from public.titulos_pagar t
left join public.de_para_historicos d on d.historico_id = t.historico_id
where t.data_cancelamento is null
group by 1, 2, 3, 4, 5, 6, 7, 8;

-- ---------------------------------------------------------------------------
-- Recebe os títulos que o n8n leu do ERP e grava tudo numa transação só.
--   p_desde   : primeiro dia do período lido (ex.: '2026-07-01')
--   p_titulos : array JSON, um objeto por título, com as colunas de titulos_pagar
--               + historico_erp (descrição do histórico, para cadastrar os novos)
-- Faz: cadastra histórico novo como 'pendente', insere/atualiza os títulos,
-- apaga os do período que não vieram mais (excluídos no ERP) e registra em sincronizacoes.
-- Só a chave secreta (service_role) pode chamar.
-- ---------------------------------------------------------------------------
create or replace function public.sincronizar_titulos(p_desde date, p_titulos jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sync      bigint;
  v_linhas    int;
  v_removidos int;
  v_novos     int;
begin
  if p_desde is null then
    raise exception 'p_desde é obrigatório';
  end if;
  if p_titulos is null or jsonb_typeof(p_titulos) <> 'array' or jsonb_array_length(p_titulos) = 0 then
    -- proteção: consulta do ERP vazia/errada não pode apagar o período inteiro
    raise exception 'p_titulos veio vazio; nada foi alterado';
  end if;

  insert into sincronizacoes (desde) values (p_desde) returning id into v_sync;

  create temp table _recebidos on commit drop as
  select *
  from jsonb_to_recordset(p_titulos) as x(
    id integer, empresa_id integer, filial_id integer, tipo_titulo_id integer,
    fornecedor_id integer, historico_id integer, historico_erp text, numero_titulo bigint,
    data_emissao date, data_vencimento date, data_ultimo_pagamento date, data_cancelamento date,
    valor_nominal numeric, valor_pago numeric, valor_pendente numeric,
    observacao text, erp_updated_at timestamp
  );

  if exists (select 1 from _recebidos where id is null or data_vencimento is null) then
    raise exception 'há título sem id ou sem data_vencimento';
  end if;

  -- históricos que ainda não existem no de-para entram como pendentes
  insert into de_para_historicos (historico_id, historico_erp, situacao)
  select distinct on (historico_id)
         historico_id,
         coalesce(nullif(trim(historico_erp), ''), 'Histórico ' || historico_id),
         'pendente'
  from _recebidos
  where historico_id is not null
  order by historico_id
  on conflict (historico_id) do nothing;
  get diagnostics v_novos = row_count;

  insert into titulos_pagar (
    id, empresa_id, filial_id, tipo_titulo_id, fornecedor_id, historico_id, numero_titulo,
    data_emissao, data_vencimento, data_ultimo_pagamento, data_cancelamento,
    valor_nominal, valor_pago, valor_pendente, observacao, erp_updated_at, sincronizado_em
  )
  select id, empresa_id, filial_id, tipo_titulo_id, fornecedor_id, historico_id, numero_titulo,
         data_emissao, data_vencimento, data_ultimo_pagamento, data_cancelamento,
         coalesce(valor_nominal, 0), coalesce(valor_pago, 0), coalesce(valor_pendente, 0),
         observacao, erp_updated_at, now()
  from _recebidos
  on conflict (id) do update set
    empresa_id            = excluded.empresa_id,
    filial_id             = excluded.filial_id,
    tipo_titulo_id        = excluded.tipo_titulo_id,
    fornecedor_id         = excluded.fornecedor_id,
    historico_id          = excluded.historico_id,
    numero_titulo         = excluded.numero_titulo,
    data_emissao          = excluded.data_emissao,
    data_vencimento       = excluded.data_vencimento,
    data_ultimo_pagamento = excluded.data_ultimo_pagamento,
    data_cancelamento     = excluded.data_cancelamento,
    valor_nominal         = excluded.valor_nominal,
    valor_pago            = excluded.valor_pago,
    valor_pendente        = excluded.valor_pendente,
    observacao            = excluded.observacao,
    erp_updated_at        = excluded.erp_updated_at,
    sincronizado_em       = excluded.sincronizado_em;
  get diagnostics v_linhas = row_count;

  delete from titulos_pagar t
  where t.data_vencimento >= p_desde
    and not exists (select 1 from _recebidos r where r.id = t.id);
  get diagnostics v_removidos = row_count;

  update sincronizacoes set finalizado_em = now(), linhas = v_linhas where id = v_sync;

  return jsonb_build_object(
    'sincronizacao', v_sync,
    'titulos', v_linhas,
    'removidos', v_removidos,
    'historicos_novos', v_novos
  );
end
$$;

revoke all on function public.sincronizar_titulos(date, jsonb) from public, anon, authenticated;
grant execute on function public.sincronizar_titulos(date, jsonb) to service_role;
