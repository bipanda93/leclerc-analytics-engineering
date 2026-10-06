select item_a, item_b, count(*) as n
from {{ ref('mart_mba_regles') }}
group by item_a, item_b
having count(*) > 1
