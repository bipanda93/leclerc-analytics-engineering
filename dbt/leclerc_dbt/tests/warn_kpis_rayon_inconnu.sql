{{ config(severity='warn') }}
select mois, chiffre_affaires
from {{ ref('mart_kpis_mois_rayon') }}
where rayon = 'inconnu'
