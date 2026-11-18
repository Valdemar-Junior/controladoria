-- Despesas = só títulos QUITADOS, no mês do VENCIMENTO, nada no futuro.
-- É a mesma base do "Relatório Contas a Pagar" do ERP: vencimento no período + valor_pago > 0,
-- somando o valor pago. (Base de caixa, pela data do pagamento, é outra pergunta.)
--
-- As colunas continuam as mesmas (a tela lê "total"); "nominal" é nova, no fim.
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
  sum(t.valor_pago)::numeric(14, 2)                 as total,    -- valor pago
  sum(t.valor_pago)::numeric(14, 2)                 as pago,     -- igual a total (mantida por compatibilidade)
  sum(t.valor_nominal)::numeric(14, 2)              as nominal   -- valor original do título
from public.titulos_pagar t
left join public.de_para_historicos d on d.historico_id = t.historico_id
where t.data_cancelamento is null
  and t.valor_pago > 0
  and t.data_vencimento <= current_date
group by 1, 2, 3, 4, 5, 6, 7, 8;

-- títulos com vencimento futuro não são mais copiados; limpa os que já vieram
delete from public.titulos_pagar where data_vencimento > current_date;
