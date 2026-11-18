-- Este projeto Supabase não dá acesso automático da API às tabelas novas.
-- Libera só o necessário. O RLS continua valendo por cima disso; anon (deslogado) não recebe nada.

-- Classificação: quem está logado lê e edita (tela /classificacao)
grant select, insert, update, delete on public.de_para_historicos to authenticated;

-- Despesas: quem está logado só lê (tela /despesas)
grant select on public.titulos_pagar       to authenticated;
grant select on public.sincronizacoes      to authenticated;
grant select on public.vw_despesas_mensais to authenticated;

-- Chave secreta (n8n / manutenção): acesso total
grant all on public.de_para_historicos, public.titulos_pagar, public.sincronizacoes, public.vw_despesas_mensais to service_role;
grant usage, select on sequence public.sincronizacoes_id_seq to service_role;
