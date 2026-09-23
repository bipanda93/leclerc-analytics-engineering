with source as (
    select * from {{ source('bronze', 'open_prices') }}
),

cleaned as (
    select
        product_code,
        product_name,
        price,
        currency,
        category_tag
    from source
    where currency = 'EUR'
      and price is not null
      and product_code is not null
)

select * from cleaned
