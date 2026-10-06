{{ config(materialized='table', schema='gold') }}

with daily as (
    select
        transaction_date as jour,
        round(sum(line_total), 2) as chiffre_affaires,
        count(distinct transaction_id) as nb_transactions,
        sum(quantity) as quantite_vendue,
        count(distinct customer_id) as nb_clients
    from {{ ref('stg_transactions__transactions') }}
    group by 1
),

insee as (
    select
        observation_date as mois,
        value as ipc_alimentation
    from {{ ref('stg_insee__conjoncture') }}
    where indicator = 'IPC_ALIMENTATION'
)

select
    d.jour,
    d.chiffre_affaires,
    d.nb_transactions,
    d.quantite_vendue,
    d.nb_clients,
    round(d.chiffre_affaires / d.nb_transactions, 2) as panier_moyen,
    i.ipc_alimentation
from daily d
left join insee i
    on date_trunc('month', d.jour) = i.mois
