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
