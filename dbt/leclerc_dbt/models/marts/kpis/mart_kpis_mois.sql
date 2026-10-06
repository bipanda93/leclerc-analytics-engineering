{{ config(materialized='table', schema='gold') }}

with transactions as (
    select * from {{ ref('stg_transactions__transactions') }}
),

monthly as (
    select
        date_trunc('month', transaction_date) as mois,
        round(sum(line_total), 2) as chiffre_affaires,
        sum(quantity) as quantite_vendue,
        count(distinct transaction_id) as nb_transactions,
        count(distinct customer_id) as nb_clients,
        count(distinct transaction_date) as nb_jours_couverts
    from transactions
    group by 1
)

select
    *,
    round(chiffre_affaires / nb_transactions, 2) as panier_moyen,
    round(chiffre_affaires / nb_clients, 2) as ca_par_client,
    round(chiffre_affaires / nb_jours_couverts, 2) as ca_par_jour,
    day(last_day(mois)) as nb_jours_du_mois,
    nb_jours_couverts < day(last_day(mois)) as mois_partiel
from monthly
