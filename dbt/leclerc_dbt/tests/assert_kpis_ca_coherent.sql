with par_rayon as (
    select mois, sum(chiffre_affaires) as ca
    from {{ ref('mart_kpis_mois_rayon') }}
    group by mois
)
select r.mois, r.ca, m.chiffre_affaires
from par_rayon r
join {{ ref('mart_kpis_mois') }} m on r.mois = m.mois
where abs(r.ca - m.chiffre_affaires) > 1
