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
