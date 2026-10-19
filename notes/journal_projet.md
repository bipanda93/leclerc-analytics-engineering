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

## 2026-10-06 (mart Tendances)

Mart gold.mart_tendances_jour construit et testé : 365 jours (du 23 septembre 2025 au 22 septembre 2026), chiffre d'affaires, transactions, panier moyen et IPC alimentation INSEE du mois. 343 jours ont un indice, les 22 de septembre 2026 n'en ont pas (non encore publié par l'INSEE) et restent vides. 5 tests dbt passent, dont un test qui vérifie qu'un indice manquant ne concerne que des mois postérieurs à la dernière publication.

Reste dans les marts : préparation SQL du MBA.

## 2026-10-06 (marts MBA, fin des marts)

Marts MBA construits et testés : mart_mba_paniers (270 830 lignes, 19 articles repérés par les mêmes mots-clés que les règles d'affinité du générateur) et mart_mba_regles (342 paires ordonnées avec support, confiance et lift, calculés en SQL). Parmi les 8 paires distinctes de plus fort lift (au moins 100 paniers), 5 sont des règles du générateur (lift de 10,6 à 19,0) et 3 sont des associations indirectes par cause commune. Les quatre marts (RFM, KPIs, Tendances, MBA) sont terminés. Reste : ML, Airflow, CI/CD, restitution.
## 2026-10-14 → 2026-10-19 (restitution Power BI)

### Ce qui a été construit

- Chargement des CSV Gold dans Power BI, modèle en étoile (ADR-36), table `_Mesures`.
- Thème du rapport (`restitution/powerbi/leclerc_theme.json`), menu latéral, navigateur de pages et 7 icônes Tabler (`restitution/powerbi/icones/`).
- **Vue d'ensemble** : 4 KPI avec badge d'évolution ▲/▼ coloré et valeur du mois précédent, CA par rayon, écart à la moyenne des rayons (4 meilleurs, 4 moins bons), tableau détaillé par rayon.
- **Rayons** : matrice rayons × mois en dégradé sur les 6 derniers mois complets, courbe du rayon sélectionné comparée à la médiane, croissance sur 6 mois, KPI du dernier mois complet.
- **Clients RFM** : KPI (10 000 clients, 10 % de gros acheteurs actifs qui font 49 % du CA, 6 % de clients moyens partis), clients par segment, nuage récence × montant, profil moyen par segment.
- **Panier** : 4 KPI (342 règles, lift maximum 19, confiance moyenne 13 %, 31 paires fortes), top 8 des paires par lift, nuage support × confiance coloré par force du lift, tableau des règles, segment par niveau de force (ADR-43).
- **Tendances** : CA des 30 derniers jours, CA moyen par jour, meilleur jour, évolution de l'IPC ; CA journalier avec moyenne mobile 7 jours ; CA moyen par jour de semaine ; ventes et IPC en base 100 (ADR-44).
- Reste à faire : captures des pages dans le README, pull request de `feat/powerbi` vers `main`.

### Incidents et corrections

**Montants lus comme du texte.** `CHIFFRE_AFFAIRES` utilisait le point comme séparateur décimal. Avec les paramètres régionaux français, Power Query l'a typé en texte.
Correction : changement de type avec les paramètres régionaux « Anglais (États-Unis) ». Les colonnes `MOIS` et `QUANTITE` ont perdu leur type au passage et ont été retypées.

**`mart_mba_paniers` lu en `Column1`, `Column2`.** Encodage et en-têtes mal détectés.
Correction : encodage UTF-8 forcé et « Utiliser la première ligne pour les en-têtes ». La table est au format long (une ligne par panier et par rayon), pas une colonne par rayon comme supposé au départ.

**Mauvaises relations.** Premières relations créées sur `Dates[Mois]` (texte), certaines en plusieurs-à-plusieurs, en 1:1 ou bidirectionnelles.
Correction : suppression et recréation à partir de `Dates[Date]`, en 1:* à sens unique (ADR-36).

**Erreurs DAX de saisie.**
- Deux mesures collées dans la même barre de formule : erreur de syntaxe. Une mesure par formule.
- « N'est pas une expression de table valide » : la mesure avait été saisie dans la vue Requête DAX, qui attend une table. Les mesures se créent depuis la vue Rapport avec « Nouvelle mesure ».
- Colonne `Libellé` créée comme mesure : « impossible de déterminer une valeur unique pour la colonne SEGMENT ». Une colonne calculée se crée avec « Nouvelle colonne », dans sa table.
- Espaces dans les crochets (`[ MONETARY ]`) : colonne introuvable.

**Mesures RFM vides.** `Part Champions` et `Part à risque` affichaient « -- ». Les filtres cherchaient « Champions » et « À risque », alors que dbt produit « Achats nombreux, actifs », « Achats moyens, partis »… Diagnostic par un graphique `Segments[SEGMENT]` × `Nb clients` : 5 barres différentes, donc relation correcte et noms erronés (ADR-41).

**Mesures sur la mauvaise table.** Une première `Part CA Champions` utilisait `[CA]`, qui vient de `mart_kpis_mois`, sans lien avec `Segments` : le filtre de segment n'avait aucun effet. Remplacée par `CA clients = SUM ( mart_rfm_customers[MONETARY] )`.

**Paires en double dans le classement par lift.** Le top 8 n'affichait que 4 paires différentes : chaque règle existe dans les deux sens et le lift est symétrique. Corrigé par la colonne `Sens unique` (ADR-43).

**Semaine anormale du 23 au 28 septembre 2025.** Pic à plus de 100 K€ par jour au démarrage du générateur, repéré sur la courbe journalière puis confirmé par un tableau trié sur le CA du jour. Un premier filtre posé sur le 2 septembre (mauvaise hypothèse sur la date) ne corrigeait rien ; le tableau a donné les vraies dates. Exclusion par un filtre de page (ADR-44).

**Meilleur jour : toutes les barres en couleur de mise en avant.** Le tri des jours par `Jour semaine num` ajoute un filtre sur cette colonne ; la mesure ne retirait que le filtre sur `Jour semaine` et chaque barre se croyait la meilleure. Corrigé avec `REMOVEFILTERS ( Dates[Jour semaine], Dates[Jour semaine num] )`.

**IPC trompeur sur double axe.** Les courbes ventes et IPC montaient ensemble. Un tableau de diagnostic (IPC moyen, minimum, maximum par mois) a montré des données INSEE saines (+1,4 % sur un an) : l'effet venait de l'axe secondaire étiré. Passage en base 100 sur un seul axe (ADR-44).

**Segment de dates oublié sur une plage réduite.** Le segment de la page Tendances est resté sur octobre → février pendant plusieurs réglages, ce qui changeait tous les KPI. Un segment de dates doit être remis sur la période complète avant d'enregistrer.

**Commits sur `main`.** Les premiers commits du `.pbix` ont été faits sur `main` au lieu d'une branche.
Correction : `git reset --soft origin/main`, `git rm --cached`, puis `git checkout -B feat/powerbi` et nouveau commit.

**Push refusé (HTTP 400).** Le `.pbix` (binaire de plusieurs Mo) dépassait le tampon HTTP par défaut de Git.
Correction : `git config http.postBuffer 524288000`.

**Fichier `.pbix` supprimé.** Une ancienne version, placée par erreur dans le dossier Gold, a été supprimée avec `rm` sans vérifier son contenu. La version de travail était intacte dans `powerbi/` et a été déplacée dans `restitution/powerbi/`.

**Terminal bloqué en `dquote>`.** Un commentaire `# vérifier qu'on est…` collé dans zsh : les commentaires ne sont pas actifs en mode interactif, et l'apostrophe a ouvert une chaîne. `Ctrl+C`, puis les commandes une par une sans commentaire.

### Leçons

- Vérifier le type de chaque colonne juste après le chargement, avant de construire quoi que ce soit dessus.
- Avant d'écrire un filtre sur du texte, afficher les valeurs réelles de la colonne.
- Une mesure ne peut filtrer qu'à travers les relations du modèle : vérifier de quelle table vient chaque mesure.
- Sauvegarder souvent, et ne jamais supprimer un fichier sans avoir vérifié qu'il existe une autre copie.
- Avant de corriger une anomalie, la localiser précisément (date, valeur) avec un tableau de diagnostic plutôt que de supposer.
- Un graphique à deux axes compare des formes, pas des ampleurs : pour comparer deux séries d'unités différentes, les ramener en base 100.
- Le `.pbix` est un binaire : Git ne montre aucune différence entre deux versions. Le format projet Power BI (PBIP), qui enregistre le modèle et les pages en texte, serait plus adapté au suivi de version.
