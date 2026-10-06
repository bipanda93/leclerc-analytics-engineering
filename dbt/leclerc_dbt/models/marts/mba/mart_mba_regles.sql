{{ config(materialized='table', schema='gold') }}

with total as (
    select count(distinct transaction_id) as n
    from {{ ref('stg_transactions__transactions') }}
),

items as (
    select item, count(*) as n_item
    from {{ ref('mart_mba_paniers') }}
    group by item
),

paires as (
    select
        a.item as item_a,
        b.item as item_b,
        count(*) as n_ab
    from {{ ref('mart_mba_paniers') }} a
    join {{ ref('mart_mba_paniers') }} b
        on a.transaction_id = b.transaction_id
        and a.item <> b.item
    group by 1, 2
)

select
    p.item_a,
    p.item_b,
    p.n_ab,
    round(p.n_ab / t.n, 4) as support_ab,
    round(p.n_ab / ia.n_item, 3) as confiance,
    round((p.n_ab / ia.n_item) / (ib.n_item / t.n), 2) as lift
from paires p
cross join total t
join items ia on p.item_a = ia.item
join items ib on p.item_b = ib.item
