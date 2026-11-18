-- De-para: histórico de despesa do ERP Solidus -> classificação do financeiro
-- (grupo > categoria > subcategoria), no formato da planilha mensal do financeiro.
-- Rode uma vez no SQL Editor do Supabase (ou com `supabase db push`).

create table if not exists public.de_para_historicos (
  historico_id   integer primary key,              -- historicos_receitas_despesas.id no ERP
  historico_erp  text    not null,                 -- descrição do histórico no ERP
  situacao       text    not null default 'pendente'
                 check (situacao in ('classificado', 'fora', 'pendente')),
                 -- classificado: tem categoria | fora: não é despesa (ex.: transferência) | pendente: falta classificar
  grupo          text,
  categoria      text,
  subcategoria   text,
  obs            text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  updated_by     uuid references auth.users (id) default auth.uid(),
  constraint classificado_tem_categoria
    check (situacao <> 'classificado' or (grupo is not null and categoria is not null))
);

create or replace function public.tocar_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end $$;

drop trigger if exists de_para_historicos_updated_at on public.de_para_historicos;
create trigger de_para_historicos_updated_at
  before update on public.de_para_historicos
  for each row execute function public.tocar_updated_at();

alter table public.de_para_historicos enable row level security;

drop policy if exists "logados leem" on public.de_para_historicos;
drop policy if exists "logados gravam" on public.de_para_historicos;
create policy "logados leem"   on public.de_para_historicos for select to authenticated using (true);
create policy "logados gravam" on public.de_para_historicos for all    to authenticated using (true) with check (true);

-- O preenchimento inicial (165 históricos classificados a partir da planilha do financeiro)
-- fica em supabase/dados-locais/de_para_historicos_seed.sql, fora do git por ter dados internos da loja.
