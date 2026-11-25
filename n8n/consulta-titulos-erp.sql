-- Contas a pagar (tipo 1 e 3): vencimento do 1º dia de 2 meses atrás até o fim do 2º mês à frente.
-- (o passado alimenta a tela Despesas; o futuro alimenta a Previsão de pagamentos)
-- Para carregar um período maior uma vez, troque a linha do "desde" por: DATE '2026-07-01' AS desde,
WITH p AS (
  SELECT (date_trunc('month', current_date) - interval '2 months')::date AS desde,
         (date_trunc('month', current_date) + interval '3 months')::date AS ate
),
x AS (
  SELECT t.id, t.empresa_id, t.filial_id, t.tipo_titulo_id,
         t.pessoa_cliente_fornecedor_id AS fornecedor_id,
         coalesce(nullif(trim(pe.nome_fantasia), ''), trim(pe.nome)) AS fornecedor_nome,
         t.historico_receita_despesa_id AS historico_id,
         trim(h.descricao)              AS historico_erp,
         t.numero_titulo, t.data_emissao, t.data_vencimento, t.data_ultimo_pagamento, t.data_cancelamento,
         t.valor_nominal, t.valor_pago, t.valor_pendente, t.observacao,
         t.updated_at                   AS erp_updated_at
    FROM lojaomoveis.titulos t
    LEFT JOIN lojaomoveis.historicos_receitas_despesas h ON h.id = t.historico_receita_despesa_id
    LEFT JOIN lojaomoveis.pessoas pe ON pe.id = t.pessoa_cliente_fornecedor_id
   WHERE t.tipo_titulo_id IN (1, 3)
     AND t.data_vencimento >= (SELECT desde FROM p)
     AND t.data_vencimento <  (SELECT ate FROM p)
)
SELECT (SELECT desde FROM p)::text          AS desde,
       count(*)                             AS qtd,
       coalesce(json_agg(x), '[]'::json)    AS titulos
  FROM x;
