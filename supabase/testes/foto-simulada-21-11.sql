-- FOTO SIMULADA de sábado 21/11/2026 23h (abre a semana de 23/11), só para testar a tela.
-- Tira a foto com os dados de hoje e "volta no tempo" no que dá para reconstruir.
-- Não dá para reconstruir: mudança de valor e de vencimento feitas depois de sábado
-- (o ERP sobrescreve), e lançamento novo com data de emissão antiga.
-- Para apagar depois: delete from public.fotos where semana_inicio = '2026-11-23';

-- 1) foto da semana de 23/11 com o estado de hoje
select public.tirar_foto('2026-11-21');

-- 2) pago depois de sábado -> na foto ainda estava em aberto
update public.foto_itens i
   set valor_pago = 0, valor_pendente = i.valor_nominal
  from public.fotos f, public.titulos_pagar t
 where f.id = i.foto_id and f.semana_inicio = '2026-11-23'
   and t.id = i.titulo_id
   and t.data_ultimo_pagamento > '2026-11-21';

-- 3) cancelado depois de sábado -> estava na foto
insert into public.foto_itens (foto_id, titulo_id, filial_id, historico_id, fornecedor_id, fornecedor_nome,
                               numero_titulo, data_vencimento, valor_nominal, valor_pago, valor_pendente)
select f.id, t.id, t.filial_id, t.historico_id, t.fornecedor_id, t.fornecedor_nome,
       t.numero_titulo, t.data_vencimento, t.valor_nominal, 0, t.valor_nominal
  from public.titulos_pagar t, public.fotos f
 where f.semana_inicio = '2026-11-23'
   and t.data_cancelamento > '2026-11-21'
   and t.valor_nominal > 0
   and coalesce(t.data_emissao, '2026-11-21') <= '2026-11-21'
   and public.data_prevista(t.data_vencimento) between f.semana_inicio and f.ate
on conflict do nothing;

-- 4) emitido depois de sábado -> não estava na foto (vira imprevisto)
delete from public.foto_itens i
 using public.fotos f, public.titulos_pagar t
 where f.id = i.foto_id and f.semana_inicio = '2026-11-23'
   and t.id = i.titulo_id
   and t.data_emissao > '2026-11-21';

-- 5) recalcula os totais e marca a hora "do sábado"
update public.fotos f
   set qtd = s.qtd, total = s.total, tirada_em = '2026-11-21 23:00:00-03'
  from (select foto_id, count(*) as qtd, sum(valor_nominal) as total
          from public.foto_itens group by foto_id) s
 where s.foto_id = f.id and f.semana_inicio = '2026-11-23';

select semana_inicio, ate, tirada_em, qtd, total from public.fotos;
