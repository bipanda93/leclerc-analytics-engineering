## 2026-09-18

Journée de mise en place complète de l'ingestion Leclerc : repo, 
environnement conda,
Airbyte self-hosté, deux Sources opérationnelles (Open Food Facts CSV, 
Open Prices Parquet)
synchronisées vers Snowflake Bronze, gouvernance RBAC posée avec comptes 
de service dédiés.
Plusieurs incidents réels rencontrés et résolus (voir 
incidents_2026-09-18.md) — bon matériau
de discussion pour la partie "gestion d'incidents" en entretien.

Reste à faire : scripts Transactions/Trends, profiles.yml dbt, premiers 
modèles.

## 2026-09-22

Bloc 1 du script `transactions_generator.py` terminé et testé : connexion 
Snowflake, requête de catégorisation (29 rayons), récupération en 
DataFrame — 578 089 produits, distribution conforme à l'exploration SQL de 
la veille. Plusieurs incidents de débogage (voir incidents_2026-09-22.md), 
résolus.

La logique d'exploration SQL ayant servi à construire les 29 rayons a été 
extraite dans `snowflake/exploration_categorisation_rayons.sql` et 
commitée, pour ne pas rester perdue dans un Workspace Snowsight.

Rédaction de `docs/decisions_architecture.md` (11 ADR) — architecture 
d'ingestion, gouvernance RBAC, méthodologie de catégorisation, et deux 
scopes explicitement écartés (A/B testing, classification supervisée pour 
enrichir la couverture) avec justification.

Reste à faire sur le script : tables de poids saisonniers/affinité, 
génération des clients, boucle de génération des transactions, prix, 
écriture vers Bronze.

## 2026-09-22 (suite)

Script transactions_generator.py terminé de bout en bout — blocs 3 à 7 (poids par rayon dérivés du panier moyen Kantar Worldpanel pondéré par les volumes réels Open Food Facts, saisonnalité sur 7 rayons, règles d'affinité probabilistes, génération de 10 000 clients avec 3 profils de fréquence, prix validés contre des données réelles françaises 2026, écriture vers Bronze). Plusieurs incidents de débogage résolus (voir incidents_2026-09-22.md).

Run final : 10 000 clients, 175 664 transactions, 1 492 481 lignes — cohérent avec les paramètres théoriques (moyenne ~17,6 transactions/client, ~8,5 articles/panier).

Bronze est maintenant peuplé sur 3 des 4 sources (Open Food Facts, Open Prices, Transactions). Reste Google Trends avant de démarrer dbt.


## 2026-09-23

Script `insee_conjoncture_extract.py` créé et terminé — pivot décidé en 
amont depuis Google Trends (pytrends archivé) vers l'API SDMX gratuite de 
l'INSEE. Indicateur IPC Alimentation France (idbank 011813717) récupéré, 
parsé (XML/ElementTree), écrit dans LECLERC.BRONZE.INSEE_CONJONCTURE — 368 
observations, 1996-01 à 2026-08.

Refactoring : `snowflake_utils.py` créé pour centraliser la connexion 
Snowflake, partagé entre `transactions_generator.py` et ce nouveau script 
— élimine la duplication de la logique `.env`/connexion.

Bronze est maintenant peuplé sur les 4 sources prévues (Open Food Facts, 
Open Prices, Transactions, INSEE Conjoncture). Prochaine étape : 
profiles.yml dbt, puis premiers modèles staging.

## 2026-09-23 (suite)

Projet dbt initialisé (`dbt init`) dans `dbt/leclerc_dbt/`. Authentification par mot de passe encore acceptée par Snowflake malgré la deadline officielle du 31 août 2026 (enforcement rolling, compte pas encore basculé). Connexion validée par `dbt debug` — LECLERC_DBT_SVC / LECLERC_DBT_TRANSFORMER, schema par défaut SILVER. profiles.yml correctement généré hors repo (~/.dbt/profiles.yml).

Les 4 sources sont dans Bronze, dbt est connecté. Prochaine étape : premiers modèles staging.

## 2026-09-23 (staging dbt)

Les 4 modèles staging créés et validés : stg_openfoodfacts__products (578 089, correction du bug code-barres Number→VARCHAR, ADR-8 enfin traité), stg_open_prices__prices (228 758, filtré EUR + code non nul), stg_transactions__transactions (1 482 041), stg_insee__conjoncture (368, period converti en DATE). Chaque requête validée manuellement dans Snowsight avant d'être figée en fichier .sql avec Jinja — même méthode que pour la catégorisation OFF il y a quelques jours.

RBAC complété : GRANT SELECT ON FUTURE TABLES/VIEWS posé sur BRONZE et SILVER pour ACCOUNTADMIN, pour ne plus revivre l'incident d'accès manquant à chaque nouvel objet créé.

dbt run complet validé (4/4 modèles, exécution parallèle ~4s). Prochaine étape : modèles intermediate (jointures entre sources), puis les marts (RFM, MBA, KPIs, Tendances).

## 2026-10-05 / 2026-10-06 (mart RFM)

Premier mart construit : gold.mart_rfm_customers, 10 000 clients, calculé avec une date de référence dérivée des données (MAX de transaction_date) plutôt que CURRENT_DATE. Les seuils ont été choisis un par un en lisant les percentiles des vraies données, avec une prédiction avant chaque requête. Constats : les extrémités du mart retrouvent les profils programmés dans le générateur ; le montant (total cumulé) recoupe presque entièrement la fréquence ; les plages d'achats du générateur ne ressemblent pas à des clients de supermarché, d'où le renommage des groupes de fréquence par volume (faible/moyenne/élevée) plutôt qu'une régénération des données.

Cinq segments définis (achats nombreux/moyens/faibles, actifs ou partis), colonne segment ajoutée au mart avec un else 'non classé' défensif. 10 tests dbt passent.

Reste dans les marts : KPIs (enrichi par rayon), préparation SQL du MBA, Tendances (Transactions + INSEE).

## 2026-10-06 (jointure Transactions × Produits)

Avant de construire le mart KPIs, contrôle de la jointure avec le catalogue produits : 99,85 % au départ, 100 % après correction (clé de jointure numérique dans le staging). Aucune duplication de lignes.

## 2026-10-06 (mart KPIs)

Deux marts KPIs construits et testés : mart_kpis_mois_rayon (377 lignes, mois × rayon) et mart_kpis_mois (13 lignes, panier moyen, chiffre d'affaires par client et par jour, indicateur de mois partiel). 10 tests dbt passent, dont un test qui vérifie que les deux marts donnent le même chiffre d'affaires par mois. Constat sur le générateur : la hausse des transactions (de 8 733 en octobre 2025 à 22 549 en août 2026) vient du biais de dates des profils, pas d'une tendance de consommation.

Reste dans les marts : préparation SQL du MBA, Tendances (Transactions × INSEE).
