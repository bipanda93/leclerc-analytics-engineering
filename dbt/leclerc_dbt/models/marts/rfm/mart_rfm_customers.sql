{{ config(materialized='table', schema='gold') }}

with transactions as (
    select * from {{ ref('stg_transactions__transactions') }}
),

reference_date as (
    select max(transaction_date) as ref_date
    from transactions
),

customer_aggregates as (
    select
        customer_id,
        max(transaction_date) as last_purchase_date,
        count(distinct transaction_id) as frequency,
        sum(line_total) as monetary
    from transactions
    group by customer_id
),

rfm as (
    select
        c.customer_id,
        datediff('day', c.last_purchase_date, r.ref_date) as recency,
        c.frequency,
        round(c.monetary, 2) as monetary
    from customer_aggregates c
    cross join reference_date r
)

select
    *,
    -- recence : moins de 30 jours = recent, plus de 60 = parti
    case
        when recency < 30 then 'récent'
        when recency > 60 then 'parti'
        else 'entre deux'
    end as groupe_recence,
    -- frequence : 5 achats ou moins, de 6 a 20, plus de 20
    case
        when frequency <= 5 then 'faible'
        when frequency <= 20 then 'moyenne'
        else 'élevée'
    end as groupe_frequence,
    -- montant : sous 500, de 500 a moins de 4000, 4000 et plus
    case
        when monetary < 500 then 'petit'
        when monetary < 4000 then 'moyen'
        else 'gros'
    end as groupe_montant
from rfm