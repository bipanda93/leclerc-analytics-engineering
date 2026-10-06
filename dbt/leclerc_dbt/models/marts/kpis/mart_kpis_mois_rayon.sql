{{ config(materialized='table', schema='gold') }}

with transactions as (
    select * from {{ ref('stg_transactions__transactions') }}
),

products as (
    select product_code_num, rayon
    from {{ ref('stg_openfoodfacts__products') }}
),

joined as (
    select
        t.transaction_id,
        t.customer_id,
        date_trunc('month', t.transaction_date) as mois,
        coalesce(p.rayon, 'inconnu') as rayon,
        t.quantity,
        t.line_total
    from transactions t
    left join products p
        on try_to_double(t.product_code) = p.product_code_num
),

monthly as (
    select
        mois,
        rayon,
        round(sum(line_total), 2) as chiffre_affaires,
        sum(quantity) as quantite_vendue,
        count(distinct transaction_id) as nb_transactions_rayon,
        count(distinct customer_id) as nb_clients
    from joined
    group by mois, rayon
)

select
    *,
    round(chiffre_affaires / nb_transactions_rayon, 2) as depense_moyenne_par_transaction,
    round(100 * chiffre_affaires / sum(chiffre_affaires) over (partition by mois), 1) as part_ca_mois_pct
from monthly
