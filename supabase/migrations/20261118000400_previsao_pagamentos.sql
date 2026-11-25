-- Previsão de pagamentos: foto semanal (sábado 23h) + comparação com o que aconteceu.
--
-- Regras:
--   * tudo pelo VENCIMENTO;
--   * vencimento no sábado/domingo é pago na segunda -> "data prevista" = segunda seguinte;
--   * semana de pagamento = segunda a sexta (chave = a segunda-feira);
--   * a foto de sábado 23h abre a semana da segunda seguinte e guarda os títulos ABERTOS e PAGOS
--     com data prevista dessa semana até o fim do mês seguinte (cancelados e zerados ficam fora);
--   * cada semana é comparada com a foto que a abriu; semana futura usa a foto mais recente (projeção).

-- ---------------------------------------------------------------------------
-- 1) nome do fornecedor nos títulos
-- ---------------------------------------------------------------------------
alter table public.titulos_pagar add column if not exists fornecedor_nome text;

-- sincronizar_titulos passa a gravar fornecedor_nome (resto igual)
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
    raise exception 'p_titulos veio vazio; nada foi alterado';
  end if;

  insert into sincronizacoes (desde) values (p_desde) returning id into v_sync;

  create temp table _recebidos on commit drop as
  select *
  from jsonb_to_recordset(p_titulos) as x(
    id integer, empresa_id integer, filial_id integer, tipo_titulo_id integer,
    fornecedor_id integer, fornecedor_nome text, historico_id integer, historico_erp text, numero_titulo bigint,
    data_emissao date, data_vencimento date, data_ultimo_pagamento date, data_cancelamento date,
    valor_nominal numeric, valor_pago numeric, valor_pendente numeric,
    observacao text, erp_updated_at timestamp
  );

  if exists (select 1 from _recebidos where id is null or data_vencimento is null) then
    raise exception 'há título sem id ou sem data_vencimento';
  end if;

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
    id, empresa_id, filial_id, tipo_titulo_id, fornecedor_id, fornecedor_nome, historico_id, numero_titulo,
    data_emissao, data_vencimento, data_ultimo_pagamento, data_cancelamento,
    valor_nominal, valor_pago, valor_pendente, observacao, erp_updated_at, sincronizado_em
  )
  select id, empresa_id, filial_id, tipo_titulo_id, fornecedor_id, nullif(trim(fornecedor_nome), ''), historico_id, numero_titulo,
         data_emissao, data_vencimento, data_ultimo_pagamento, data_cancelamento,
         coalesce(valor_nominal, 0), coalesce(valor_pago, 0), coalesce(valor_pendente, 0),
         observacao, erp_updated_at, now()
  from _recebidos
  on conflict (id) do update set
    empresa_id            = excluded.empresa_id,
    filial_id             = excluded.filial_id,
    tipo_titulo_id        = excluded.tipo_titulo_id,
    fornecedor_id         = excluded.fornecedor_id,
    fornecedor_nome       = excluded.fornecedor_nome,
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

  return jsonb_build_object('sincronizacao', v_sync, 'titulos', v_linhas, 'removidos', v_removidos, 'historicos_novos', v_novos);
end
$$;

revoke all on function public.sincronizar_titulos(date, jsonb) from public, anon, authenticated;
grant execute on function public.sincronizar_titulos(date, jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- 2) data prevista: sábado e domingo vão para a segunda
-- ---------------------------------------------------------------------------
create or replace function public.data_prevista(d date)
returns date
language sql
immutable
as $$
  select case extract(isodow from d)
           when 6 then d + 2
           when 7 then d + 1
           else d
         end
$$;

-- ---------------------------------------------------------------------------
-- 3) fotos
-- ---------------------------------------------------------------------------
create table if not exists public.fotos (
  id             bigint generated always as identity primary key,
  semana_inicio  date not null unique,      -- segunda-feira da semana que a foto abre
  ate            date not null,             -- última data prevista guardada
  tirada_em      timestamptz not null default now(),
  qtd            integer,
  total          numeric(14, 2)
);

create table if not exists public.foto_itens (
  foto_id          bigint not null references public.fotos (id) on delete cascade,
  titulo_id        integer not null,
  filial_id        integer,
  historico_id     integer,
  fornecedor_id    integer,
  fornecedor_nome  text,
  numero_titulo    bigint,
  data_vencimento  date not null,
  valor_nominal    numeric(14, 2) not null,
  valor_pago       numeric(14, 2) not null,
  valor_pendente   numeric(14, 2) not null,
  primary key (foto_id, titulo_id)
);
create index if not exists foto_itens_titulo_idx on public.foto_itens (titulo_id);

alter table public.fotos      enable row level security;
alter table public.foto_itens enable row level security;
drop policy if exists "logados leem" on public.fotos;
drop policy if exists "logados leem" on public.foto_itens;
create policy "logados leem" on public.fotos      for select to authenticated using (true);
create policy "logados leem" on public.foto_itens for select to authenticated using (true);
grant select on public.fotos, public.foto_itens to authenticated;
grant all    on public.fotos, public.foto_itens to service_role;

-- Tira (ou refaz) a foto da semana. p_semana = um dia de referência (padrão: hoje em Brasília):
-- sábado/domingo abrem a semana da segunda seguinte; dia útil, a própria semana.
-- Chamada pelo n8n logo após sincronizar.
create or replace function public.tirar_foto(p_semana date default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  -- +2 dias: sábado/domingo caem na semana da segunda seguinte; dia útil fica na própria semana
  v_semana date := date_trunc('week', coalesce(p_semana, (now() at time zone 'America/Fortaleza')::date) + 2)::date;
  v_ate    date := (date_trunc('month', v_semana) + interval '2 months' - interval '1 day')::date;
  v_foto   bigint;
  v_qtd    int;
  v_total  numeric;
begin
  delete from fotos where semana_inicio = v_semana;
  insert into fotos (semana_inicio, ate) values (v_semana, v_ate) returning id into v_foto;

  insert into foto_itens (foto_id, titulo_id, filial_id, historico_id, fornecedor_id, fornecedor_nome,
                          numero_titulo, data_vencimento, valor_nominal, valor_pago, valor_pendente)
  select v_foto, t.id, t.filial_id, t.historico_id, t.fornecedor_id, t.fornecedor_nome,
         t.numero_titulo, t.data_vencimento, t.valor_nominal, t.valor_pago, t.valor_pendente
  from titulos_pagar t
  where t.data_cancelamento is null
    and t.valor_nominal > 0
    and data_prevista(t.data_vencimento) between v_semana and v_ate;

  select count(*), coalesce(sum(valor_nominal), 0) into v_qtd, v_total from foto_itens where foto_id = v_foto;
  update fotos set qtd = v_qtd, total = v_total where id = v_foto;

  return jsonb_build_object('foto', v_foto, 'semana', v_semana, 'ate', v_ate, 'titulos', v_qtd, 'total', v_total);
end
$$;

revoke all on function public.tirar_foto(date) from public, anon, authenticated;
grant execute on function public.tirar_foto(date) to service_role;

-- ---------------------------------------------------------------------------
-- 4) previsão: uma linha por título por semana, com a situação
-- ---------------------------------------------------------------------------
-- situacao:
--   pago        estava na foto e foi pago            a_pagar      estava na foto, segue em aberto
--   pago_antes  já estava pago quando a foto saiu    adiado       estava na foto, o vencimento mudou de semana
--   cancelado   estava na foto e foi cancelado/zerado
--   imprevisto  não estava na foto                   veio_adiado  estava na foto, mas em outra semana
--   sem_foto    semana sem nenhuma foto (só realizado)
create or replace function public.previsao_titulos(p_de date, p_ate date)
returns table (
  semana date, data_ref date, situacao text, projecao boolean, foto_semana date,
  titulo_id integer, numero_titulo bigint, filial_id integer, historico_id integer, historico_erp text,
  grupo text, categoria text, subcategoria text, fornecedor_nome text,
  venc_foto date, venc_atual date, valor_foto numeric, valor_atual numeric,
  valor_pago numeric, valor_pendente numeric, data_pagamento date
)
language sql
stable
security invoker
set search_path = public
as $$
  with semanas as (
    select gs::date as semana
    from generate_series(date_trunc('week', p_de), date_trunc('week', p_ate), interval '7 days') gs
  ),
  sf as (
    select s.semana, f.id as foto_id, f.semana_inicio as foto_semana
    from semanas s
    left join lateral (
      select id, semana_inicio from fotos where semana_inicio <= s.semana order by semana_inicio desc limit 1
    ) f on true
  ),
  prev as (
    select sf.semana, sf.foto_semana, i.titulo_id, i.filial_id, i.historico_id, i.fornecedor_nome,
           i.numero_titulo, i.data_vencimento, i.valor_nominal, i.valor_pago, i.valor_pendente,
           data_prevista(i.data_vencimento) as dp_foto
    from sf
    join foto_itens i on i.foto_id = sf.foto_id
    where date_trunc('week', data_prevista(i.data_vencimento))::date = sf.semana
  ),
  atual as (
    select t.*,
           data_prevista(t.data_vencimento)                      as dp,
           (t.valor_pago > 0 and t.valor_pendente <= 0)           as quitado,
           (t.data_cancelamento is not null or t.valor_nominal <= 0) as fora
    from titulos_pagar t
  ),
  linhas as (
    select p.semana, p.dp_foto as data_ref,
           case
             when a.id is null or a.fora                               then 'cancelado'
             when date_trunc('week', a.dp)::date <> p.semana           then 'adiado'
             when p.valor_pendente <= 0 and p.valor_pago > 0           then 'pago_antes'
             when a.quitado                                            then 'pago'
             else 'a_pagar'
           end as situacao,
           p.foto_semana < p.semana as projecao, p.foto_semana,
           p.titulo_id, coalesce(a.numero_titulo, p.numero_titulo) as numero_titulo,
           coalesce(a.filial_id, p.filial_id) as filial_id, coalesce(a.historico_id, p.historico_id) as historico_id,
           coalesce(a.fornecedor_nome, p.fornecedor_nome) as fornecedor_nome,
           p.data_vencimento as venc_foto, a.data_vencimento as venc_atual,
           case when p.valor_pendente <= 0 and p.valor_pago > 0 then p.valor_pago else p.valor_nominal end as valor_foto,
           case when a.quitado then a.valor_pago else a.valor_nominal end as valor_atual,
           a.valor_pago, a.valor_pendente, a.data_ultimo_pagamento as data_pagamento
    from prev p
    left join atual a on a.id = p.titulo_id
    union all
    select sf.semana, a.dp,
           case
             when sf.foto_id is null then 'sem_foto'
             when exists (select 1 from foto_itens i where i.foto_id = sf.foto_id and i.titulo_id = a.id) then 'veio_adiado'
             else 'imprevisto'
           end,
           sf.foto_semana < sf.semana, sf.foto_semana,
           a.id, a.numero_titulo, a.filial_id, a.historico_id, a.fornecedor_nome,
           null::date, a.data_vencimento, null::numeric,
           case when a.quitado then a.valor_pago else a.valor_nominal end,
           a.valor_pago, a.valor_pendente, a.data_ultimo_pagamento
    from atual a
    join sf on sf.semana = date_trunc('week', a.dp)::date
    where not a.fora
      and not exists (select 1 from prev p where p.titulo_id = a.id and p.semana = sf.semana)
  )
  select l.semana, l.data_ref, l.situacao, coalesce(l.projecao, false), l.foto_semana,
         l.titulo_id, l.numero_titulo, l.filial_id, l.historico_id,
         coalesce(d.historico_erp, 'Histórico ' || l.historico_id),
         case when d.situacao = 'classificado' then d.grupo end,
         case when d.situacao = 'classificado' then d.categoria end,
         case when d.situacao = 'classificado' then d.subcategoria end,
         l.fornecedor_nome, l.venc_foto, l.venc_atual, l.valor_foto, l.valor_atual,
         l.valor_pago, l.valor_pendente, l.data_pagamento
  from linhas l
  left join de_para_historicos d on d.historico_id = l.historico_id
  where l.data_ref between p_de and p_ate
    and coalesce(d.situacao, '') <> 'fora'
  order by l.data_ref, l.titulo_id
$$;

grant execute on function public.previsao_titulos(date, date) to authenticated, service_role;
