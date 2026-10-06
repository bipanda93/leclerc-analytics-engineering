{{ config(materialized='table', schema='gold') }}

with lignes as (
    select
        transaction_id,
        lower(product_name) as nom
    from {{ ref('stg_transactions__transactions') }}
),

mots as (
    select column1 as item, column2 as mot
    from values
        ('pates', 'pâtes'), ('pates', 'spaghetti'), ('pates', 'penne'), ('pates', 'tagliatelle'),
        ('sauce_tomate', 'sauce tomate'), ('sauce_tomate', 'sauce bolognaise'),
        ('cafe', 'café'),
        ('sucre', 'sucre'),
        ('biscuit', 'biscuit'),
        ('apero_sale', 'chips'), ('apero_sale', 'cacahuète'), ('apero_sale', 'apéritif'),
        ('biere', 'bière'),
        ('soda', 'soda'),
        ('jus', 'jus'),
        ('pain', 'pain'), ('pain', 'baguette'),
        ('confiture', 'confiture'),
        ('beurre', 'beurre'),
        ('fromage', 'fromage'),
        ('grillades', 'merguez'), ('grillades', 'saucisse'), ('grillades', 'steak haché'), ('grillades', 'brochette'),
        ('ketchup', 'ketchup'),
        ('moutarde', 'moutarde'),
        ('sauce_barbecue', 'sauce barbecue'),
        ('the', 'thé'),
        ('chocolat', 'chocolat')
)

select distinct
    l.transaction_id,
    m.item
from lignes l
join mots m
    on l.nom like '%' || m.mot || '%'
