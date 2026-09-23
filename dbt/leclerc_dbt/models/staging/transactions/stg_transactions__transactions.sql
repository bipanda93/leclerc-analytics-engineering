with source as (
    select * from {{ source('bronze', 'transactions') }}
),

cleaned as (
    select
        transaction_id,
        customer_id,
        transaction_date,
        product_code,
        product_name,
        quantity,
        unit_price,
        line_total
    from source
    where customer_id is not null
      and product_code is not null
      and unit_price is not null
)

select * from cleaned
