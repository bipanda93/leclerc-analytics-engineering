select mois, rayon, count(*) as n
from {{ ref('mart_kpis_mois_rayon') }}
group by mois, rayon
having count(*) > 1
