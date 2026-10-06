# Incidents — 2026-10-05 / 2026-10-06 (mart RFM)

## Schéma SILVER_gold créé à la place de GOLD
Premier run du mart avec schema='gold' : dbt a écrit dans SILVER_gold (le schéma par défaut collé devant le nom demandé). La macro generate_schema_name existait bien sur le disque mais n'était pas chargée (562 macros au premier run, 563 au second) : le fichier n'était probablement pas encore sauvegardé. Fix : relance après sauvegarde, puis suppression du schéma parasite.

## Suppression de SILVER_gold : rôle non assignable
USE ROLE LECLERC_DBT_TRANSFORMER échoue pour l'utilisateur humain (le rôle n'est assigné qu'au compte de service LECLERC_DBT_SVC). Fix : GRANT OWNERSHIP du schéma à ACCOUNTADMIN, puis DROP SCHEMA.

## ACCOUNTADMIN sans accès à une table créée par dbt (3e occurrence)
Même cause que pour Bronze et Silver : Snowflake n'accorde aucun accès automatique aux objets créés par un autre rôle. Fix durable : GRANT SELECT ON FUTURE TABLES/VIEWS posé au niveau de la base LECLERC, qui couvre tout futur schéma.

## datediff : erreurs de nom et de syntaxe
`datediff(day, ...)` a été lu comme un nom de colonne (identifiant 'DAY' invalide) ; la version 'date_diff' avec underscore n'existe pas chez Snowflake. Fix : datediff('day', ...) avec l'unité entre guillemets simples.

## Deux modèles collés dans le même fichier SQL
Erreur "unexpected 'with'" ligne 38 : l'ancienne et la nouvelle version du mart se suivaient dans le fichier. Un commentaire coupé en deux lignes au collage aurait cassé le SQL juste après. Fix : réécriture du fichier entier par le terminal (cat > fichier << 'EOF'), qui écrase tout d'un coup et garde l'indentation.

## YAML des tests mal formé
Erreur de parsing ligne 5 : bloc de colonne sans la ligne `columns:` au-dessus, puis deux versions du fichier collées l'une sous l'autre, dont une sans indentation. Fix : réécriture complète par le terminal. À retenir : dbt parse attrape les erreurs de structure YAML et de Jinja, mais pas les erreurs de SQL, que seul Snowflake juge au dbt run.

## 584 codes produits introuvables dans la jointure Transactions × Produits
Le contrôle de jointure donnait 99,85 % : 2 284 lignes de transactions (584 codes distincts) sans rayon. Les produits existaient toujours dans Bronze, mais le même nombre s'écrit différemment en texte côté Python (entier complet) et côté Snowflake (conversion du FLOAT). Ces codes font de 16 à 28 chiffres, ce ne sont pas de vrais codes-barres. Ma première correction (convertir en NUMBER(38,0)) a échoué : au moins un code dépasse 38 chiffres, ce qui aurait aussi fait planter le dbt run. Fix retenu : comparer en nombre flottant (voir ADR-26).

## ref() inutilisable dans Snowsight
Une requête de mart copiée dans Snowsight avec ref() et des noms de tables sans base ni schéma ne peut pas s'exécuter : ref() n'existe que dans dbt. Fix : noms complets (LECLERC.SILVER...) pour tester, ref() uniquement dans les fichiers dbt.

## nb_transactions_rayon : une somme qui ne veut rien dire
Dans le mart par mois et par rayon, la somme des transactions de chaque rayon donne environ 5,9 fois le vrai nombre de transactions du mois, car un panier touche en moyenne près de 6 rayons. Le panier moyen global ne peut donc pas se déduire de ce mart. Fix : second mart, au grain d'un mois, qui compte les vraies transactions.
