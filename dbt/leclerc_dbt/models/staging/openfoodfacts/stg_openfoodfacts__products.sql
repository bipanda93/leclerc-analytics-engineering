with source as (
    select * from {{ source('bronze', 'openfoodfacts_products') }}
),

cleaned as (
    select
        cast(code as varchar) as product_code,
        product_name,
        brands,
        case
            when categories_tags ilike '%en:eggs%' then 'Œufs'
            when categories_tags ilike '%en:dietary-supplements%' then 
'Compléments alimentaires'
            when categories_tags ilike '%en:coffees%' then 'Café'
            when categories_tags ilike '%en:cheeses%' then 'Fromages'
            when categories_tags ilike '%en:dairies%' then 'Produits 
laitiers'
            when categories_tags ilike '%en:pickles%' then 'Pickles'
            when categories_tags ilike '%en:canned-foods%' or 
categories_tags ilike '%en:foies-gras%' then 'Conserves'
            when categories_tags ilike '%en:seafood%' then 'Poissons'
            when categories_tags ilike '%en:biscuits%' then 'Biscuits'
            when categories_tags ilike '%en:cocoa-and-its-products%' then 
'Chocolat/cacao'
            when categories_tags ilike '%en:confectioneries%' then 
'Confiseries'
            when categories_tags ilike '%en:frozen-foods%' then 'Surgelés'
            when categories_tags ilike '%en:compotes%' then 'Compotes'
            when categories_tags ilike '%en:seeds%' then 'Graines'
            when categories_tags ilike '%en:salty-snacks%' or 
categories_tags ilike '%en:nuts-and-their-products%' or categories_tags 
ilike '%en:nuts%' then 'Snacks salés'
            when categories_tags ilike 
'%en:fruits-and-vegetables-based-foods%' then 'Fruits & légumes'
            when categories_tags ilike '%en:fats%' then 'Huiles/matières 
grasses'
            when categories_tags ilike '%en:vinegars%' then 'Vinaigres'
            when categories_tags ilike '%en:desserts%' then 'Desserts'
            when categories_tags ilike '%en:sandwiches%' then 'Sandwiches'
            when categories_tags ilike '%en:sweet-snacks%' then 'Snacks 
sucrés'
            when categories_tags ilike '%en:sauces%' then 'Sauces'
            when categories_tags ilike '%en:breads%' then 'Pain'
            when categories_tags ilike '%en:cereals-and-potatoes%' then 
'Féculents/pâtes'
            when categories_tags ilike '%en:meals%' then 'Plats préparés'
            when categories_tags ilike '%en:spreads%' then 'Pâtes à 
tartiner'
            when categories_tags ilike '%en:meats-and-their-products%' 
then 'Viandes/charcuterie'
            when categories_tags ilike '%en:condiments%' or 
categories_tags ilike '%en:spices%' then 'Condiments/Épices'
            when categories_tags ilike '%en:beverages%' then 'Boissons'
        end as rayon
    from source
    where countries_tags ilike '%en:france%'
      and product_name is not null
      and code is not null
)

select * from cleaned
where rayon is not null
