#on_fait_des_Categories°_CTE

WITH Produits_france AS(
    SELECT categories_tags
    from LECLERC.BRONZE.OPENFOODFACTS_PRODUCTS
    WHERE countries_tags ILIKE '%france%'
)
SELECT TRIM(value::string) AS tag, COUNT(*) AS nb_produits
FROM Produits_france,
LATERAL FLATTEN(INPUT => SPLIT(categories_tags, ','))
GROUP BY tag
ORDER BY nb_produits DESC;

#CALCULE_DU_NB_TOTAL_TAG

WITH Produits_france AS (
    SELECT categories_tags
    FROM LECLERC.BRONZE.OPENFOODFACTS_PRODUCTS
    WHERE countries_tags ILIKE '%en:france%'
)
SELECT COUNT(DISTINCT TRIM(value::string)) AS nb_total_tag
FROM Produits_france,
LATERAL FLATTEN(INPUT => SPLIT(categories_tags, ','))

#PRODUITS_PAR_RAYONS

WITH Produits_france AS(
    SELECT code, categories_tags
    FROM LECLERC.BRONZE.OPENFOODFACTS_PRODUCTS
    WHERE countries_tags ILIKE '%france%'
),
rayons AS (
    SELECT * FROM VALUES
        ('Boissons', 'en:beverages'),
        ('Viandes/charcuterie', 'en:meats-and-their-products'),
        ('Produits laitiers', 'en:dairies'),
        ('Fromages', 'en:cheeses'),
        ('Poissons', 'en:seafood'),
        ('Snacks sucrés', 'en:sweet-snacks'),
        ('Snacks salés', 'en:salty-snacks'),
        ('Confiseries', 'en:confectioneries'),
        ('Chocolat/cacao', 'en:cocoa-and-its-products'),
        ('Biscuits', 'en:biscuits'),
        ('Desserts', 'en:desserts'),
        ('Sauces', 'en:sauces'),
        ('Conserves', 'en:canned-foods'),
        ('Surgelés', 'en:frozen-foods'),
        ('Pain', 'en:breads'),
        ('Plats préparés', 'en:meals'),
        ('Pâtes à tartiner', 'en:spreads'),
        ('Féculents/pâtes alimentaires', 'en:cereals-and-potatoes')
     AS t(rayon, tag_rayon)   
),
produit_par_rayon as (
    select r.rayon, f.code, f.categories_tags
    from Produits_france f
    join rayons r on f.categories_tags ilike '%' || r.tag_rayon || '%'
),
sous_tags AS (
    select rayon, trim(value::string) as sous_tag
    from produit_par_rayon,
    lateral flatten(input => SPLIT(categories_tags, ','))
)
select rayon, sous_tag, count(*) as nb_produits
from sous_tags
where sous_tag not like '%france%' and sous_tag not in ( select tag_rayon 
from rayons)
group by rayon, sous_tag
qualify row_number() over (partition by rayon order by nb_produits desc) 
<= 8
order by rayon, nb_produits desc;

#MEILLEUR_CATEGORIE_DE_PRODUITS

WITH france_products AS (
    SELECT code, categories_tags
    FROM LECLERC.BRONZE.OPENFOODFACTS_PRODUCTS
    WHERE countries_tags ILIKE '%en:france%'
      AND product_name IS NOT NULL
),
categorise AS (
    SELECT
        code,
        CASE
            WHEN categories_tags ILIKE '%en:cheeses%' THEN 'Fromages'
            WHEN categories_tags ILIKE '%en:dairies%' THEN 'Produits 
laitiers'
            WHEN categories_tags ILIKE '%en:canned-foods%' THEN 
'Conserves'
            WHEN categories_tags ILIKE '%en:seafood%' THEN 'Poissons'
            WHEN categories_tags ILIKE '%en:biscuits%' THEN 'Biscuits'
            WHEN categories_tags ILIKE '%en:cocoa-and-its-products%' THEN 
'Chocolat/cacao'
            WHEN categories_tags ILIKE '%en:confectioneries%' THEN 
'Confiseries'
            WHEN categories_tags ILIKE '%en:frozen-foods%' THEN 'Surgelés'
            WHEN categories_tags ILIKE '%en:desserts%' THEN 'Desserts'
            WHEN categories_tags ILIKE '%en:sweet-snacks%' THEN 'Snacks 
sucrés'
            WHEN categories_tags ILIKE '%en:salty-snacks%' THEN 'Snacks 
salés'
            WHEN categories_tags ILIKE '%en:sauces%' THEN 'Sauces'
            WHEN categories_tags ILIKE '%en:breads%' THEN 'Pain'
            WHEN categories_tags ILIKE '%en:cereals-and-potatoes%' THEN 
'Féculents/pâtes'
            WHEN categories_tags ILIKE '%en:meals%' THEN 'Plats préparés'
            WHEN categories_tags ILIKE '%en:spreads%' THEN 'Pâtes à 
tartiner'
            WHEN categories_tags ILIKE '%en:meats-and-their-products%' 
THEN 'Viandes/charcuterie'
            WHEN categories_tags ILIKE '%en:beverages%' THEN 'Boissons'
            ELSE NULL
        END AS rayon
    FROM france_products
)
SELECT
    COALESCE(rayon, '(non catégorisé)') AS rayon,
    COUNT(*) AS nb_produits,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM categorise
GROUP BY rayon
ORDER BY nb_produits DESC;

#REDUCTION_%NON_CATEGORISE 

WITH france_products AS (
    SELECT code, categories_tags
    FROM LECLERC.BRONZE.OPENFOODFACTS_PRODUCTS
    WHERE countries_tags ILIKE '%en:france%'
      AND product_name IS NOT NULL
),
categorise AS (
    SELECT
        code, categories_tags,
        CASE
            WHEN categories_tags ILIKE '%en:cheeses%' THEN 'Fromages'
            WHEN categories_tags ILIKE '%en:dairies%' THEN 'Produits 
laitiers'
            WHEN categories_tags ILIKE '%en:canned-foods%' THEN 
'Conserves'
            WHEN categories_tags ILIKE '%en:seafood%' THEN 'Poissons'
            WHEN categories_tags ILIKE '%en:biscuits%' THEN 'Biscuits'
            WHEN categories_tags ILIKE '%en:cocoa-and-its-products%' THEN 
'Chocolat/cacao'
            WHEN categories_tags ILIKE '%en:confectioneries%' THEN 
'Confiseries'
            WHEN categories_tags ILIKE '%en:frozen-foods%' THEN 'Surgelés'
            WHEN categories_tags ILIKE '%en:desserts%' THEN 'Desserts'
            WHEN categories_tags ILIKE '%en:sweet-snacks%' THEN 'Snacks 
sucrés'
            WHEN categories_tags ILIKE '%en:salty-snacks%' THEN 'Snacks 
salés'
            WHEN categories_tags ILIKE '%en:sauces%' THEN 'Sauces'
            WHEN categories_tags ILIKE '%en:breads%' THEN 'Pain'
            WHEN categories_tags ILIKE '%en:cereals-and-potatoes%' THEN 
'Féculents/pâtes'
            WHEN categories_tags ILIKE '%en:meals%' THEN 'Plats préparés'
            WHEN categories_tags ILIKE '%en:spreads%' THEN 'Pâtes à 
tartiner'
            WHEN categories_tags ILIKE '%en:meats-and-their-products%' 
THEN 'Viandes/charcuterie'
            WHEN categories_tags ILIKE '%en:beverages%' THEN 'Boissons'
            ELSE NULL
        END AS rayon
    FROM france_products
)
SELECT
    CASE WHEN categories_tags IS NULL OR TRIM(categories_tags) = '' THEN 
'Sans aucun tag' ELSE 'A des tags, mais aucun ne matche' END AS raison,
    COUNT(*) AS nb_produits
FROM categorise
WHERE rayon IS NULL
GROUP BY raison;

#VERIFICATION_DE_CATEGORIE_FRUIT_LEGUME

WITH france_products AS (
    SELECT code, categories_tags
    FROM LECLERC.BRONZE.OPENFOODFACTS_PRODUCTS
    WHERE countries_tags ILIKE '%en:france%'
      AND product_name IS NOT NULL
      AND categories_tags IS NOT NULL AND TRIM(categories_tags) != ''
),
non_matches AS (
    SELECT code, categories_tags
    FROM france_products
    WHERE NOT (
        categories_tags ILIKE '%en:cheeses%' OR categories_tags ILIKE 
'%en:dairies%' OR
        categories_tags ILIKE '%en:canned-foods%' OR categories_tags ILIKE 
'%en:seafood%' OR
        categories_tags ILIKE '%en:biscuits%' OR categories_tags ILIKE 
'%en:cocoa-and-its-products%' OR
        categories_tags ILIKE '%en:confectioneries%' OR categories_tags 
ILIKE '%en:frozen-foods%' OR
        categories_tags ILIKE '%en:desserts%' OR categories_tags ILIKE 
'%en:sweet-snacks%' OR
        categories_tags ILIKE '%en:salty-snacks%' OR categories_tags ILIKE 
'%en:sauces%' OR
        categories_tags ILIKE '%en:breads%' OR categories_tags ILIKE 
'%en:cereals-and-potatoes%' OR
        categories_tags ILIKE '%en:meals%' OR categories_tags ILIKE 
'%en:spreads%' OR
        categories_tags ILIKE '%en:meats-and-their-products%' OR 
categories_tags ILIKE '%en:beverages%'
    )
)
SELECT TRIM(value::string) AS tag, COUNT(*) AS nb_produits
FROM non_matches,
LATERAL FLATTEN(input => SPLIT(categories_tags, ','))
WHERE TRIM(value::string) NOT ILIKE '%plant-based%'
GROUP BY tag
ORDER BY nb_produits DESC
LIMIT 20;

#SIMPLIFICATION_DES_CATEGORIE_FRUIT_LEGUME

WITH france_products AS (
    SELECT code, categories_tags
    FROM LECLERC.BRONZE.OPENFOODFACTS_PRODUCTS
    WHERE countries_tags ILIKE '%en:france%'
      AND product_name IS NOT NULL
),
categorise AS (
    SELECT
        code,
        CASE
            WHEN categories_tags ILIKE '%en:cheeses%' THEN 'Fromages'
            WHEN categories_tags ILIKE '%en:dairies%' THEN 'Produits 
laitiers'
            WHEN categories_tags ILIKE '%en:canned-foods%' THEN 
'Conserves'
            WHEN categories_tags ILIKE '%en:seafood%' THEN 'Poissons'
            WHEN categories_tags ILIKE '%en:biscuits%' THEN 'Biscuits'
            WHEN categories_tags ILIKE '%en:cocoa-and-its-products%' THEN 
'Chocolat/cacao'
            WHEN categories_tags ILIKE '%en:confectioneries%' THEN 
'Confiseries'
            WHEN categories_tags ILIKE '%en:frozen-foods%' THEN 'Surgelés'
            WHEN categories_tags ILIKE 
'%en:fruits-and-vegetables-based-foods%' THEN 'Fruits & légumes'
            WHEN categories_tags ILIKE '%en:fats%' THEN 'Matières 
grasses/huiles'
            WHEN categories_tags ILIKE '%en:desserts%' THEN 'Desserts'
            WHEN categories_tags ILIKE '%en:sweet-snacks%' THEN 'Snacks 
sucrés'
            WHEN categories_tags ILIKE '%en:salty-snacks%' THEN 'Snacks 
salés'
            WHEN categories_tags ILIKE '%en:sauces%' THEN 'Sauces'
            WHEN categories_tags ILIKE '%en:breads%' THEN 'Pain'
            WHEN categories_tags ILIKE '%en:cereals-and-potatoes%' THEN 
'Féculents/pâtes'
            WHEN categories_tags ILIKE '%en:meals%' THEN 'Plats préparés'
            WHEN categories_tags ILIKE '%en:spreads%' THEN 'Pâtes à 
tartiner'
            WHEN categories_tags ILIKE '%en:meats-and-their-products%' 
THEN 'Viandes/charcuterie'
            WHEN categories_tags ILIKE '%en:beverages%' THEN 'Boissons'
            ELSE NULL
        END AS rayon
    FROM france_products
)
SELECT
    COALESCE(rayon, '(non catégorisé)') AS rayon,
    COUNT(*) AS nb_produits,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM categorise
GROUP BY rayon
ORDER BY nb_produits DESC;

#CREATION_DE_LA_COMPOTE

WITH france_products AS (
    SELECT categories_tags
    FROM LECLERC.BRONZE.OPENFOODFACTS_PRODUCTS
    WHERE countries_tags ILIKE '%en:france%'
)
SELECT TRIM(value::string) AS tag, COUNT(*) AS nb_produits
FROM france_products,
LATERAL FLATTEN(input => SPLIT(categories_tags, ','))
WHERE TRIM(value::string) ILIKE '%compote%'
GROUP BY tag
ORDER BY nb_produits DESC
LIMIT 20;

#DETAILS_DES_PRODUITS_NON_CATEGORISE

WITH france_products AS (
    SELECT code, categories_tags
    FROM LECLERC.BRONZE.OPENFOODFACTS_PRODUCTS
    WHERE countries_tags ILIKE '%en:france%'
      AND product_name IS NOT NULL
      AND categories_tags IS NOT NULL AND TRIM(categories_tags) != ''
),
non_matches AS (
    SELECT code, categories_tags
    FROM france_products
    WHERE NOT (
        categories_tags ILIKE '%en:cheeses%' OR categories_tags ILIKE 
'%en:dairies%' OR
        categories_tags ILIKE '%en:canned-foods%' OR categories_tags ILIKE 
'%en:seafood%' OR
        categories_tags ILIKE '%en:biscuits%' OR categories_tags ILIKE 
'%en:cocoa-and-its-products%' OR
        categories_tags ILIKE '%en:confectioneries%' OR categories_tags 
ILIKE '%en:frozen-foods%' OR
        categories_tags ILIKE '%en:compotes%' OR categories_tags ILIKE 
'%en:fruits-and-vegetables-based-foods%' OR
        categories_tags ILIKE '%en:fats%' OR categories_tags ILIKE 
'%en:desserts%' OR
        categories_tags ILIKE '%en:sweet-snacks%' OR categories_tags ILIKE 
'%en:salty-snacks%' OR
        categories_tags ILIKE '%en:sauces%' OR categories_tags ILIKE 
'%en:breads%' OR
        categories_tags ILIKE '%en:cereals-and-potatoes%' OR 
categories_tags ILIKE '%en:meals%' OR
        categories_tags ILIKE '%en:spreads%' OR categories_tags ILIKE 
'%en:meats-and-their-products%' OR
        categories_tags ILIKE '%en:beverages%'
    )
)
SELECT TRIM(value::string) AS tag, COUNT(*) AS nb_produits
FROM non_matches,
LATERAL FLATTEN(input => SPLIT(categories_tags, ','))
WHERE TRIM(value::string) NOT ILIKE '%plant-based%'
GROUP BY tag
ORDER BY nb_produits DESC
LIMIT 25;

#NOUVELLES_CATEGORIES

WITH france_products AS (
    SELECT code, categories_tags
    FROM LECLERC.BRONZE.OPENFOODFACTS_PRODUCTS
    WHERE countries_tags ILIKE '%en:france%'
      AND product_name IS NOT NULL
),
categorise AS (
    SELECT
        code,
        CASE
            WHEN categories_tags ILIKE '%en:eggs%' THEN 'Œufs'
            WHEN categories_tags ILIKE '%en:dietary-supplements%' THEN 
'Compléments alimentaires'
            WHEN categories_tags ILIKE '%en:coffees%' THEN 'Café'
            WHEN categories_tags ILIKE '%en:cheeses%' THEN 'Fromages'
            WHEN categories_tags ILIKE '%en:dairies%' THEN 'Produits 
laitiers'
            WHEN categories_tags ILIKE '%en:pickles%' THEN 'Pickles'
            WHEN categories_tags ILIKE '%en:canned-foods%' OR 
categories_tags ILIKE '%en:foies-gras%' THEN 'Conserves'
            WHEN categories_tags ILIKE '%en:seafood%' THEN 'Poissons'
            WHEN categories_tags ILIKE '%en:biscuits%' THEN 'Biscuits'
            WHEN categories_tags ILIKE '%en:cocoa-and-its-products%' THEN 
'Chocolat/cacao'
            WHEN categories_tags ILIKE '%en:confectioneries%' THEN 
'Confiseries'
            WHEN categories_tags ILIKE '%en:frozen-foods%' THEN 'Surgelés'
            WHEN categories_tags ILIKE '%en:compotes%' THEN 'Compotes'
            WHEN categories_tags ILIKE '%en:seeds%' THEN 'Graines'
            WHEN categories_tags ILIKE '%en:salty-snacks%' OR 
categories_tags ILIKE '%en:nuts-and-their-products%' OR categories_tags 
ILIKE '%en:nuts%' THEN 'Snacks salés'
            WHEN categories_tags ILIKE 
'%en:fruits-and-vegetables-based-foods%' THEN 'Fruits & légumes'
            WHEN categories_tags ILIKE '%en:fats%' THEN 'Huiles/matières 
grasses'
            WHEN categories_tags ILIKE '%en:vinegars%' THEN 'Vinaigres'
            WHEN categories_tags ILIKE '%en:desserts%' THEN 'Desserts'
            WHEN categories_tags ILIKE '%en:sandwiches%' THEN 'Sandwiches'
            WHEN categories_tags ILIKE '%en:sweet-snacks%' THEN 'Snacks 
sucrés'
            WHEN categories_tags ILIKE '%en:sauces%' THEN 'Sauces'
            WHEN categories_tags ILIKE '%en:breads%' THEN 'Pain'
            WHEN categories_tags ILIKE '%en:cereals-and-potatoes%' THEN 
'Féculents/pâtes'
            WHEN categories_tags ILIKE '%en:meals%' THEN 'Plats préparés'
            WHEN categories_tags ILIKE '%en:spreads%' THEN 'Pâtes à 
tartiner'
            WHEN categories_tags ILIKE '%en:meats-and-their-products%' 
THEN 'Viandes/charcuterie'
            WHEN categories_tags ILIKE '%en:condiments%' OR 
categories_tags ILIKE '%en:spices%' THEN 'Condiments/Épices'
            WHEN categories_tags ILIKE '%en:beverages%' THEN 'Boissons'
            ELSE NULL
        END AS rayon
    FROM france_products
)
SELECT
    COALESCE(rayon, '(non catégorisé)') AS rayon,
    COUNT(*) AS nb_produits,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM categorise
GROUP BY rayon
ORDER BY nb_produits DESC;

#CTE_FINAL_PROPRE_1

WITH categorized AS (
    SELECT
        code,
        product_name,
        brands,
        CASE
            WHEN categories_tags ILIKE '%en:eggs%' THEN 'Œufs'
            WHEN categories_tags ILIKE '%en:dietary-supplements%' THEN 
'Compléments alimentaires'
            WHEN categories_tags ILIKE '%en:coffees%' THEN 'Café'
            WHEN categories_tags ILIKE '%en:cheeses%' THEN 'Fromages'
            WHEN categories_tags ILIKE '%en:dairies%' THEN 'Produits 
laitiers'
            WHEN categories_tags ILIKE '%en:pickles%' THEN 'Pickles'
            WHEN categories_tags ILIKE '%en:canned-foods%' OR 
categories_tags ILIKE '%en:foies-gras%' THEN 'Conserves'
            WHEN categories_tags ILIKE '%en:seafood%' THEN 'Poissons'
            WHEN categories_tags ILIKE '%en:biscuits%' THEN 'Biscuits'
            WHEN categories_tags ILIKE '%en:cocoa-and-its-products%' THEN 
'Chocolat/cacao'
            WHEN categories_tags ILIKE '%en:confectioneries%' THEN 
'Confiseries'
            WHEN categories_tags ILIKE '%en:frozen-foods%' THEN 'Surgelés'
            WHEN categories_tags ILIKE '%en:compotes%' THEN 'Compotes'
            WHEN categories_tags ILIKE '%en:seeds%' THEN 'Graines'
            WHEN categories_tags ILIKE '%en:salty-snacks%' OR 
categories_tags ILIKE '%en:nuts-and-their-products%' OR categories_tags 
ILIKE '%en:nuts%' THEN 'Snacks salés'
            WHEN categories_tags ILIKE 
'%en:fruits-and-vegetables-based-foods%' THEN 'Fruits & légumes'
            WHEN categories_tags ILIKE '%en:fats%' THEN 'Huiles/matières 
grasses'
            WHEN categories_tags ILIKE '%en:vinegars%' THEN 'Vinaigres'
            WHEN categories_tags ILIKE '%en:desserts%' THEN 'Desserts'
            WHEN categories_tags ILIKE '%en:sandwiches%' THEN 'Sandwiches'
            WHEN categories_tags ILIKE '%en:sweet-snacks%' THEN 'Snacks 
sucrés'
            WHEN categories_tags ILIKE '%en:sauces%' THEN 'Sauces'
            WHEN categories_tags ILIKE '%en:breads%' THEN 'Pain'
            WHEN categories_tags ILIKE '%en:cereals-and-potatoes%' THEN 
'Féculents/pâtes'
            WHEN categories_tags ILIKE '%en:meals%' THEN 'Plats préparés'
            WHEN categories_tags ILIKE '%en:spreads%' THEN 'Pâtes à 
tartiner'
            WHEN categories_tags ILIKE '%en:meats-and-their-products%' 
THEN 'Viandes/charcuterie'
            WHEN categories_tags ILIKE '%en:condiments%' OR 
categories_tags ILIKE '%en:spices%' THEN 'Condiments/Épices'
            WHEN categories_tags ILIKE '%en:beverages%' THEN 'Boissons'
        END AS rayon
    FROM LECLERC.BRONZE.OPENFOODFACTS_PRODUCTS
    WHERE countries_tags ILIKE '%en:france%'
      AND product_name IS NOT NULL
)
SELECT code, product_name, brands, rayon
FROM categorized
WHERE rayon IS NOT NULL;

WITH france_products AS (
    SELECT code, categories_tags
    FROM LECLERC.BRONZE.OPENFOODFACTS_PRODUCTS
    WHERE countries_tags ILIKE '%en:france%'
      AND product_name IS NOT NULL
      AND categories_tags IS NOT NULL AND TRIM(categories_tags) != ''
),
non_matches AS (
    SELECT code, categories_tags
    FROM france_products
    WHERE NOT (
        categories_tags ILIKE '%en:eggs%' OR categories_tags ILIKE 
'%en:dietary-supplements%' OR
        categories_tags ILIKE '%en:coffees%' OR categories_tags ILIKE 
'%en:cheeses%' OR
        categories_tags ILIKE '%en:dairies%' OR categories_tags ILIKE 
'%en:pickles%' OR
        categories_tags ILIKE '%en:canned-foods%' OR categories_tags ILIKE 
'%en:foies-gras%' OR
        categories_tags ILIKE '%en:seafood%' OR categories_tags ILIKE 
'%en:biscuits%' OR
        categories_tags ILIKE '%en:cocoa-and-its-products%' OR 
categories_tags ILIKE '%en:confectioneries%' OR
        categories_tags ILIKE '%en:frozen-foods%' OR categories_tags ILIKE 
'%en:compotes%' OR
        categories_tags ILIKE '%en:seeds%' OR categories_tags ILIKE 
'%en:salty-snacks%' OR
        categories_tags ILIKE '%en:nuts-and-their-products%' OR 
categories_tags ILIKE '%en:nuts%' OR
        categories_tags ILIKE '%en:fruits-and-vegetables-based-foods%' OR 
categories_tags ILIKE '%en:fats%' OR
        categories_tags ILIKE '%en:vinegars%' OR categories_tags ILIKE 
'%en:desserts%' OR
        categories_tags ILIKE '%en:sandwiches%' OR categories_tags ILIKE 
'%en:sweet-snacks%' OR
        categories_tags ILIKE '%en:sauces%' OR categories_tags ILIKE 
'%en:breads%' OR
        categories_tags ILIKE '%en:cereals-and-potatoes%' OR 
categories_tags ILIKE '%en:meals%' OR
        categories_tags ILIKE '%en:spreads%' OR categories_tags ILIKE 
'%en:meats-and-their-products%' OR
        categories_tags ILIKE '%en:condiments%' OR categories_tags ILIKE 
'%en:spices%' OR
        categories_tags ILIKE '%en:beverages%'
    )
)
SELECT TRIM(value::string) AS tag, COUNT(*) AS nb_produits
FROM non_matches,
LATERAL FLATTEN(input => SPLIT(categories_tags, ','))
WHERE TRIM(value::string) NOT ILIKE '%plant-based%'
GROUP BY tag
ORDER BY nb_produits DESC


