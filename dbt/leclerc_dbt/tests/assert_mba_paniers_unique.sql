select transaction_id, item, count(*) as n
from {{ ref('mart_mba_paniers') }}
group by transaction_id, item
having count(*) > 1
