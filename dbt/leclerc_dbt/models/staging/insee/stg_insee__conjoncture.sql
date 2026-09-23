with source as (
    select * from {{ source('bronze', 'insee_conjoncture') }}
),

cleaned as (
    select
        to_date(period || '-01', 'YYYY-MM-DD') as observation_date,
        value,
        indicator
    from source
    where value is not null
)

select * from cleaned
