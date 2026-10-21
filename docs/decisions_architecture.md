# Décisions d'architecture — Leclerc Analytics Engineering

## ADR-1 — Ingestion via Airbyte plutôt que Fivetran

**Contexte** : deux options pour l'ingestion batch. Fivetran est 
exclusivement cloud, aucune option self-hosted.
**Décision** : Airbyte OSS self-hosted (Docker/Kubernetes via `abctl`).
**Justification** : cohérence avec le reste de la stack (Docker local), 
zéro coût, alignement avec le vocabulaire des offres Analytics Engineer 
2026 ("Fivetran, Airbyte" cités explicitement comme outils d'ingestion 
attendus).

## ADR-2 — Connecteur File pré-construit plutôt que Connector Builder 
custom

**Contexte** : Open Food Facts et Open Prices sont des fichiers statiques 
exposés en HTTPS, sans logique d'API à gérer.
**Décision** : connecteur "File (CSV, JSON, Excel, Feather, Parquet)" 
pré-construit.
**Justification** : pas de pagination à gérer, zéro code de connecteur à 
écrire.
**Limite connue** : le connecteur infère le schéma (types de colonnes) 
depuis le contenu du fichier, indépendamment des Reader Options passées à 
pandas — `dtype: str` force la lecture en texte mais n'empêche pas Airbyte 
de classer une colonne numérique-en-apparence comme `Number` (voir ADR-8).

## ADR-3 — Export CSV plutôt que JSONL/Parquet complet pour Open Food 
Facts

**Contexte** : le dump complet (JSONL ou Parquet) pèse ~7,7 Go ; aucun 
export filtré par pays n'existe côté Open Food Facts.
**Décision** : export CSV allégé (~0,9 Go, champs essentiels uniquement).
**Justification** : préserve les crédits du trial Snowflake ; le filtrage 
géographique (France) et catégoriel se fait en aval, à la lecture (voir 
ADR-6).

## ADR-4 — Snowflake sur Azure

**Décision** : compte trial Snowflake, cloud provider Azure.
**Justification** : familiarité acquise sur le projet SNCF ; le cloud 
provider sous-jacent n'a aucun impact fonctionnel sur Airbyte/dbt/scripts 
Python.

## ADR-5 — Gouvernance RBAC : rôles de service dédiés

**Décision** : deux rôles distincts — `LECLERC_AIRBYTE_LOADER` (écriture 
Bronze + `CREATE SCHEMA` sur la base, requis par le schéma technique 
interne `airbyte_internal` du connecteur Snowflake) et 
`LECLERC_DBT_TRANSFORMER` (lecture Bronze, écriture Silver/Gold) — chacun 
avec son utilisateur de service dédié, jamais `ACCOUNTADMIN` dans les 
identifiants applicatifs.
**Justification** : principe du moindre privilège ; un compte de service 
compromis reste cantonné à son périmètre (Bronze en écriture, ou Bronze en 
lecture + Silver/Gold), jamais à l'administration du compte.
**Incident lié** : plusieurs rotations de mots de passe nécessaires après 
exposition accidentelle en clair dans des messages/fichiers versionnés — 
voir `notes/incidents_*.md`.

## ADR-6 — Catégorisation produit par règles empiriques (29 rayons)

**Contexte** : `categories_tags` d'Open Food Facts est un champ 
multi-valeurs, non normalisé, sans équivalent "rayon supermarché".
**Décision** : 29 rayons construits itérativement par exploration SQL 
(`LATERAL FLATTEN` + comptages réels), pas par supposition — chaque rayon 
mappé à un tag OFF parent (ex. `en:meats-and-their-products` → 
Viandes/charcuterie), avec un ordre de priorité explicite (spécifique 
avant générique) pour gérer les chevauchements de la taxonomie.
**Résultat mesuré** : 93,8% de couverture sur les produits ayant au moins 
un tag (511 362 produits sans aucun tag exclus, donnée manquante à la 
source, non récupérable).
**Duplication assumée** : cette logique vit dans 
`transactions_generator.py` (nécessaire pour générer les paniers) et 
pourrait un jour être réécrite en modèle dbt staging si réutilisée pour de 
l'analyse — pas fait aujourd'hui, le générateur en a besoin avant que dbt 
n'existe dans la chaîne pour cette donnée.

## ADR-7 — Panier moyen (Kantar Worldpanel) comme calibrage des poids

**Contexte** : les volumes du catalogue Open Food Facts reflètent 
l'activité des contributeurs, pas les vraies habitudes d'achat françaises.
**Décision** : utiliser une répartition budgétaire réelle (Kantar 
Worldpanel France 2025, via une source secondaire) pour pondérer la 
fréquence relative des rayons dans le générateur de transactions, 
indépendamment du volume catalogue OFF.
**Limite** : source secondaire (blog), pas le rapport Kantar primaire — 
traité comme ordre de grandeur indicatif.

## ADR-8 — Limite connue : `code` typé Number (zéros de tête perdus)

**Constat** : Airbyte a inféré le champ `code` (code-barres) comme 
`Number` plutôt que `String`. Les zéros de tête (courants sur les EAN-13 
dérivés d'UPC-A) sont perdus dès l'ingestion — non récupérables a 
posteriori par un simple `CAST`.
**Impact** : risque de jointure silencieusement vide entre Open Food Facts 
et Open Prices sur les produits concernés.
**Décision** : non corrigé à la source pour l'instant (impliquerait un 
Full Refresh ~11 min pour un gain marginal sur ce projet) ; à corriger en 
modèle dbt staging si la jointure par code-barres devient critique.

## ADR-9 — Classification supervisée écartée pour enrichir la 
catégorisation

**Contexte** : ~511k produits sans aucun tag pourraient en théorie être 
catégorisés via un classifieur entraîné sur les produits déjà taggés (nom 
→ rayon).
**Décision** : non retenu.
**Justification** : circularité méthodologique — un modèle supervisé sur 
nos propres règles ne peut que les reproduire (y compris leurs angles 
morts), jamais découvrir une catégorie non anticipée. Un clustering 
non-supervisé (embeddings + k-means/HDBSCAN) serait la bonne approche pour 
une vraie découverte, mais sort du scope retenu pour ce projet.

## ADR-10 — A/B testing non retenu

**Constat** : extension naturelle du volet promos (XGBoost) — valider 
statistiquement l'effet d'une promo plutôt que de se fier uniquement à la 
prédiction.
**Décision** : non implémenté, pour rester dans le scope temporel du 
projet.

## ADR-11 — Positionnement vs SNCF (batch/ELT vs streaming)

Leclerc et SNCF démontrent deux philosophies distinctes, pas un simple 
choix d'outils différents : SNCF fait du streaming-ETL (Spark Streaming 
transforme en transit, avant l'atterrissage dans Delta Lake) ; Leclerc 
fait de l'ELT batch pur (Airbyte charge le brut sans y toucher, dbt 
transforme après, dans l'entrepôt). Le choix correspond à la nature de 
chaque source, pas à une préférence arbitraire.

## ADR-12 — Pondération des rayons : panier moyen Kantar × volumes OFF

**Décision** : le poids de base de chaque rayon combine deux sources — la part budgétaire de sa famille Kantar Worldpanel (France 2025), répartie entre les rayons de cette famille au prorata de leur volume réel dans Open Food Facts.
**Justification** : Kantar donne la vraie fréquence d'achat par grande famille (pas biaisée par l'activité contributive OFF) ; le volume OFF sert uniquement à répartir ce budget entre rayons plus fins au sein d'une même famille.
**Limite assumée** : 5 rayons (Condiments/Épices, Compléments alimentaires) n'ont aucun équivalent Kantar — poids arbitraire faible (2%) plutôt qu'une vraie donnée de marché.

## ADR-13 — Saisonnalité : 7 rayons, ordres de grandeur intuitifs

**Décision** : seuls 7 rayons (Surgelés, Boissons, Chocolat/cacao, Confiseries, Plats préparés, Viandes/charcuterie, Sandwiches) reçoivent un multiplicateur mensuel ; le reste garde un poids plat toute l'année.
**Justification** : ce sont les seuls rayons avec un signal saisonnier français bien reconnu (été = grillades/glaces/pique-nique, décembre = chocolat/plats festifs). Forcer une saisonnalité sur les autres rayons aurait été de l'invention pure.
**Limite assumée** : les multiplicateurs eux-mêmes ne sont pas sourcés (pas de données Kantar mensuelles disponibles) — ordres de grandeur construits, pas mesurés.

## ADR-14 — Perte de temporalité sur Open Prices

**Contexte** : un deuxième bug "Timestamp is not JSON serializable" (distinct de celui déjà documenté en ADR-8, même symptôme, cause différente) a forcé l'exclusion de 6 champs à consonance temporelle (date, proof_date, created, updated, proof_created, proof_updated, location_created, location_updated), pas seulement les 2 initialement identifiés.
**Décision** : accepté — aucun moyen de savoir quand un prix Open Prices a été observé ou enregistré.
**Justification** : produit, prix, catégorie et localisation restent intacts (suffisant pour KPIs/MBA) ; l'angle "évolution du prix dans le temps" sort du scope de ce projet.

## ADR-15 — Prix synthétiques validés contre données réelles 2026

**Décision** : les fourchettes de prix par rayon (repli quand aucun prix réel Open Prices n'est disponible) ont été vérifiées contre des prix français réels 2026 (lait, pain, œufs, fromage, viande, fruits/légumes, boissons) plutôt que purement inventées.
**Ajustement issu de cette vérification** : Boissons scindé — vin/champagne isolés dans une fourchette propre (KEYWORD_PRICE_OVERRIDES sur le nom du produit) pour ne pas fausser la fourchette du reste des boissons (eau, soda, bière).
**Limite assumée** : seuls 8 rayons sur 26 ont été vérifiés contre une vraie source ; le reste reste construit par intuition, même niveau de confiance que la saisonnalité (ADR-13).

## ADR-16 — Bruit de tagging résiduel Open Food Facts, non corrigé

**Constat** : certains produits portent un tag de catégorie manifestement erroné à la source (ex. "Fruits de mer" classé sous `en:cocoa-and-its-products`).
**Décision** : non corrigé — ce n'est pas un bug de la logique de catégorisation (`CASE WHEN` déjà validé sur 93,8% de couverture), mais une erreur de donnée contributive, hors du contrôle du pipeline.
**Justification** : sur 578 089 produits, quelques erreurs de tagging isolées ont un impact négligeable sur des paniers agrégés ; construire une détection d'anomalies dédiée sortirait du scope du projet, même logique que ADR-9/ADR-10.

## ADR-17 — Pivot Google Trends → INSEE Conjoncture

**Contexte** : `pytrends`, prévu dès l'architecture initiale, s'est révélé archivé (dépôt GitHub gelé depuis avril 2025, non maintenu), avec un comportement de rate-limiting imprévisible.
**Décision** : remplacé par l'API SDMX gratuite et sans clé de l'INSEE (bdm.insee.fr), indicateur IPC Alimentation France (idbank 011813717), mensuel depuis 1996.
**Justification** : source gouvernementale officielle, activement maintenue, cohérente avec le choix déjà fait pour Open Prices (data.gouv.fr) ; un indice de consommation réel est aussi un signal de demande plus direct qu'un proxy d'intérêt de recherche.
**Limite assumée** : un seul indicateur global (prix alimentaire), pas de déclinaison par rayon — contrairement à ce qu'aurait pu permettre un suivi de mots-clés Google Trends par catégorie.

## ADR-18 — Module snowflake_utils.py partagé

**Décision** : extraction de la logique de connexion Snowflake (chargement `.env`, validation, `get_connection()`) dans `ingestion/snowflake_utils.py`, importé par tous les scripts d'ingestion plutôt que dupliqué.
**Justification** : évite la duplication à mesure que le nombre de scripts augmente (Transactions, INSEE, et au-delà) ; un seul endroit à modifier si les identifiants ou la logique de connexion changent.

## ADR-19 — Authentification dbt par mot de passe malgré la deadline du 31 août 2026

**Contexte** : Snowflake annonce la fin du support de l'authentification par mot de passe pour les connexions dbt à partir du 31 août 2026 (enforcement rolling par compte, même mécanisme que celui déjà noté pour Airbyte).
**Constat** : à la date de mise en place (23 septembre 2026), le compte accepte toujours l'authentification par mot de passe — `dbt debug` réussi.
**Décision** : conservé tel quel pour l'instant plutôt que de migrer préventivement vers une authentification par paire de clés RSA.
**Risque assumé** : la connexion peut cesser de fonctionner sans préavis si le compte bascule dans la fenêtre d'enforcement en cours de projet — cohérent avec le risque déjà documenté pour Airbyte (même cause, deux symptômes potentiels).

## ADR-20 — Modèles staging : un par source, sans déduplication ni incrémental

**Décision** : 4 modèles staging en vues simples (pas de table matérialisée, pas de logique incrémentale), chacun listant explicitement les colonnes utiles plutôt qu'un `select *`.
**Justification** : les 4 sources sont déjà à un volume raisonnable pour dbt (le plus gros, Transactions, ~1,5M lignes, se recalcule en vue en une fraction de seconde) ; aucun doublon identifié ne justifie une déduplication CTE+ROW_NUMBER à ce stade.
**Limite assumée** : si le volume de Transactions grossissait significativement (plusieurs runs successifs sans purge, par exemple), une matérialisation incrémentale deviendrait pertinente — non implémentée pour rester dans le scope du projet.

## ADR-21 — RBAC étendu : accès futur sur Bronze et Silver

**Contexte** : deux incidents distincts (22 et 23 septembre) où ACCOUNTADMIN n'avait pas accès à une table fraîchement créée par LECLERC_AIRBYTE_LOADER ou LECLERC_DBT_TRANSFORMER — Snowflake n'accorde jamais d'accès automatique aux objets créés par un autre rôle.
**Décision** : `GRANT SELECT ON FUTURE TABLES/VIEWS IN SCHEMA` posé sur BRONZE et SILVER pour ACCOUNTADMIN, couvrant tout objet futur peu importe le rôle créateur — résout la classe d'incident pour de bon, pas juste l'occurrence ponctuelle.

## ADR-22 — Récence calculée par rapport à MAX(transaction_date), pas CURRENT_DATE

**Contexte** : les transactions sont générées une seule fois et ne changent plus. Avec CURRENT_DATE, la récence de chaque client augmenterait chaque jour sans qu'aucune donnée n'ait bougé.
**Décision** : date de référence = la date la plus récente de toute la table (une seule valeur pour tous les clients). Un maximum par client donnerait une récence de 0 à tous.
**Conséquence** : le mart est reproductible, ses résultats ne dépendent pas du jour d'exécution.

## ADR-23 — Seuils RFM fixes, groupes de fréquence nommés par volume

**Décision** : seuils fixes plutôt qu'un classement en pourcentages, pour la lisibilité métier (récence : moins de 30 jours = récent, plus de 60 = parti ; fréquence : 5 achats ou moins, 6 à 20, plus de 20 ; montant : moins de 500 €, moins de 4 000 €, 4 000 € et plus). Les groupes de fréquence s'appellent faible, moyenne et élevée.
**Limite assumée** : les seuils sont liés à l'échelle de ce jeu de données. Les plages d'achats du générateur (régulier : 8 à 20 par an) ne ressemblent pas à des clients de supermarché : plus de 8 Français sur 10 font leurs courses chaque semaine (sondage Ipsos 2023). Avec une définition réaliste (2 achats par mois = occasionnel, 1 par semaine = régulier), 89,7 % des clients deviendraient occasionnels et le groupe régulier n'en compterait que 1,7 %.
**Décision sur la limite** : ne pas régénérer les données (coût de revalidation trop élevé avant la soutenance), nommer les groupes par volume plutôt que par comportement.
**Autre constat** : le montant est un total cumulé et suit le nombre d'achats ; les 1 035 clients « gros » sont exactement les 1 035 fréquence « élevée ». La segmentation repose donc sur la récence et la fréquence. Le panier moyen est traité dans le mart KPIs.

## ADR-24 — Cinq segments clients, avec else défensif et tests

**Décision** : sept cases récence × fréquence regroupées en cinq segments : Achats nombreux actifs (1 035), Achats moyens actifs (5 331), Achats moyens partis (584), Achats faibles actifs (508), Achats faibles partis (2 542). Les clients « entre deux » sont rattachés aux actifs. Un else 'non classé' évite qu'une combinaison imprévue donne un NULL silencieux.
**Tests** : not_null et accepted_values sur segment, sans 'non classé' dans la liste autorisée, pour qu'une combinaison imprévue fasse échouer le test.

## ADR-25 — Schéma GOLD via la macro generate_schema_name

**Contexte** : par défaut, dbt colle le schéma de la connexion devant le schéma demandé (SILVER_gold au lieu de GOLD).
**Décision** : macro generate_schema_name qui utilise le nom personnalisé tel quel, et le schéma par défaut sinon.
**Droits** : GRANT SELECT ON FUTURE TABLES/VIEWS posé au niveau de la base LECLERC pour ACCOUNTADMIN (étend l'ADR-21 à tout futur schéma).

## ADR-26 — Jointure Transactions × Produits sur le code numérique

**Contexte** : 584 codes produits (2 284 lignes de transactions, 0,15 %) ne se retrouvaient pas dans le modèle staging des produits. Ils font de 16 à 28 chiffres (ce ne sont pas de vrais codes-barres), sont stockés en FLOAT dans Bronze (exact sur 15 à 17 chiffres seulement) et s'écrivent différemment en texte côté Python (entier complet) et côté Snowflake (conversion du FLOAT).
**Essai écarté** : conversion en NUMBER(38,0), qui échoue car au moins un code dépasse 38 chiffres.
**Décision** : le staging garde `product_code` (texte) et ajoute `product_code_num` (le FLOAT d'origine). Les jointures se font avec `try_to_double(t.product_code) = p.product_code_num`.
**Résultat** : 1 482 041 lignes sur 1 482 041 retrouvent leur rayon (100 %), sans duplication.
**Limite** : comparaison de flottants, exacte seulement jusqu'à 15-17 chiffres ; les produits dont le code contient des lettres sont déjà perdus à l'ingestion (colonne FLOAT, voir ADR-8).

## ADR-27 — Deux marts KPIs : un par rayon, un par mois

**Contexte** : la somme de nb_transactions_rayon sur tous les rayons d'un mois vaut environ 5,9 fois le nombre réel de transactions, parce qu'un panier est compté dans chaque rayon qu'il touche.
**Décision** : mart_kpis_mois_rayon (chiffre d'affaires, quantités, clients par mois et par rayon) pour l'analyse par catégorie ; mart_kpis_mois (grain d'un mois, vraies transactions) pour le panier moyen et les indicateurs globaux. Un test dbt vérifie que les deux marts donnent le même chiffre d'affaires par mois.
**Règle** : ne jamais additionner nb_transactions_rayon entre rayons.

## ADR-28 — Mois partiels signalés plutôt que retirés

**Contexte** : la période des transactions couvre 365 jours avant le lancement du générateur, donc septembre 2025 ne compte que 8 jours et septembre 2026 que 22.
**Décision** : les mois partiels restent dans le mart, avec une colonne mois_partiel et un chiffre d'affaires par jour (ca_par_jour) comparable d'un mois à l'autre.
**Conséquence** : les tableaux de bord doivent utiliser ca_par_jour pour comparer un mois partiel aux autres, ou filtrer sur mois_partiel.

## ADR-29 — Limites du générateur visibles dans les KPIs

**Constat** : (1) les transactions mensuelles passent de 8 733 à 22 549 alors que le nombre de clients actifs reste proche de 5 400, effet probable du biais de dates des profils (fréquents vers la fin de la période, rares vers le début) et non d'une tendance de consommation ; (2) le panier moyen reste entre 107 € et 119 € tous les mois, car la taille du panier et les prix ne dépendent ni du client ni du mois ; (3) la viande pèse 41 % du chiffre d'affaires en septembre 2025, contre 25 % pour viande, poisson et charcuterie dans le budget Kantar de l'ADR-12, explication probable : les poids Kantar servent de probabilités de tirage d'un article et non de part de budget, donc les écarts de prix entre rayons déplacent la part du chiffre d'affaires.
**Décision** : ne pas régénérer les données, présenter ces écarts comme des limites du jeu de données simulé et non comme des constats sur de vrais clients.

## ADR-30 — Mart Tendances au grain journalier, indice INSEE rattaché par mois

**Décision** : une ligne par jour (365 lignes) plutôt que par mois, parce qu'un modèle de prévision comme Prophet a besoin de plus que 13 points. L'IPC alimentation, publié par mois, est rattaché à chaque jour de son mois ; les jours postérieurs au dernier mois publié (22 jours en septembre 2026) gardent un indice vide plutôt qu'une valeur reportée, pour ne pas inventer une donnée. Un test dbt vérifie qu'aucun indice ne manque avant la dernière publication.
**Limite assumée** : dans nos données simulées, les prix de transaction sont tirés au hasard et ne dépendent pas de la date, donc l'IPC n'influence en rien le chiffre d'affaires. Le chiffre d'affaires et l'indice montent tous deux au fil des mois, ce qui peut produire une corrélation positive sans aucun lien réel. L'IPC sera présenté comme une variable explicative candidate, pas comme un lien causal démontré.

## ADR-31 — Règles d'association calculées en SQL, sans Apriori

**Contexte** : le MBA était prévu à l'étape ML avec Apriori (mlxtend). Or les règles d'affinité du générateur sont toutes des paires.
**Décision** : les articles du panier sont 19 indicateurs construits sur les mêmes mots-clés que le générateur (mart_mba_paniers) ; le support, la confiance et le lift de chaque paire se calculent en SQL (mart_mba_regles, 342 paires ordonnées). Apriori ne serait utile que pour des combinaisons de trois articles ou plus, hors périmètre.
**Résultat** : parmi les 8 paires distinctes de plus fort lift (au moins 100 paniers), 5 sont des règles du générateur (café et biscuit 19,0 ; pâtes et sauce tomate 14,9 ; soda et apéritif salé 11,9 ; bière et apéritif salé 10,9 ; café et sucre 10,6) et 3 sont des associations indirectes par cause commune (soda et bière 8,7 ; sucre et biscuit 7,3 ; ketchup et sauce barbecue 6,7).
**Limites** : les articles sont repérés par texte, donc un mot court peut apparaître dans des noms inattendus ; le lift est symétrique, la confiance non (chaque paire sort deux fois, à filtrer sur item_a < item_b pour un tableau de bord) ; le support est calculé sur toutes les transactions, avec environ 1,6 article suivi par transaction, donc les paires rares sont instables (lecture à partir de 100 paniers).

## ADR-32 — Intégration continue dbt dans un schéma isolé

**Contexte** : aucune modification n'était vérifiée automatiquement avant sa fusion dans main, et une erreur dans un modèle n'apparaissait qu'au run suivant, directement en production.
**Décision** : un workflow GitHub Actions lance dbt build (10 modèles, 33 tests) à chaque pull request vers main, avec une cible ci qui écrit dans un schéma dédié, CI_PR, propriété du rôle LECLERC_DBT_TRANSFORMER. La macro generate_schema_name envoie tous les modèles dans CI_PR quand la cible est ci, pour ne jamais écrire dans SILVER ni GOLD. Les identifiants viennent des secrets du dépôt, lus par env_var() dans un profil versionné (dbt/leclerc_dbt/ci/profiles.yml) qui ne contient aucune valeur sensible.
**Alternatives écartées** : écrire dans SILVER, car une pull request défectueuse écraserait la production avant toute relecture ; un schéma par pull request, plus propre mais plus coûteux en crédits pour un projet mené seul.
**Limites** : chaque pull request reconstruit tout le projet, ce qui consomme des crédits Snowflake ; la règle qui impose une CI verte avant fusion n'est pas appliquée sur un dépôt privé avec un compte GitHub gratuit, elle le sera quand le dépôt deviendra public.

## ADR-33 — Orchestration avec Airflow 3 en local

**Contexte** : les étapes du pipeline étaient lancées à la main, sans planification, sans relance et sans arrêt automatique en cas d'erreur.
**Décision** : un DAG leclerc_daily, exécuté chaque jour à 6 h (heure de Paris), enchaîne extract_insee, dbt_build_silver, dbt_build_gold et export_gold. Airflow 3.3 tourne sous Docker Compose avec le LocalExecutor. dbt et les scripts d'ingestion tournent dans un environnement virtuel séparé (/opt/leclerc_venv), pour éviter les conflits de dépendances avec Airflow. Le profil dbt prod lit ses identifiants dans l'environnement, avec une variable de rôle distincte de celle d'Airbyte. Les synchronisations Airbyte et le générateur de transactions restent hors du DAG, car leurs données ne changent pas chaque jour.
**Alternatives écartées** : le CeleryExecutor, avec Redis et des workers, trop lourd pour un seul DAG sur un poste local ; l'installation de dbt dans le Python d'Airflow, exposée aux conflits de versions ; Cosmos, qui transformerait chaque modèle dbt en tâche, gardé comme évolution possible.
**Incidents** : (1) le code du projet était d'abord monté sous /opt/airflow, et le conteneur airflow-init, qui change le propriétaire de tout ce dossier, mettait plus de quinze minutes à démarrer ; les montages ont été déplacés vers /opt/leclerc. (2) Le premier run a échoué au test assert_tendances_ipc_manquant_historique, lancé dès l'étape de staging parce qu'un de ses parents y était sélectionné, alors que le mart qu'il vérifie n'était pas encore reconstruit avec l'indice INSEE de septembre ; l'option --indirect-selection cautious réserve désormais chaque test à l'étape où tous ses parents sont construits. L'échec a bien bloqué la reconstruction de Gold, comme prévu.
**Limites** : Airflow ne tourne que lorsque Docker est démarré sur le poste ; en production, il faudrait un orchestrateur hébergé et un exécuteur distribué.

## ADR-34 — Alertes Slack et incident de fusion d'une PR en échec

**Contexte** : la CI vérifie le code avant fusion, mais rien ne prévenait 
d'un échec à l'exécution du DAG. Par ailleurs, une PR de démonstration 
(#6, ordre Silver/Gold inversé) a été fusionnée alors qu'Airflow CI était 
rouge.

**Décision** : callback `on_failure_callback` qui envoie un message Slack 
via Incoming Webhook (URL dans `airflow/.env`, jamais commitée), déclenché 
après la relance. L'incident #6 a été corrigé par un `git revert -m 1` 
passé lui-même par une PR validée par la CI, sans modifier `main` 
directement.

**Alternatives écartées** : alertes e-mail SMTP d'Airflow (configuration 
plus lourde) ; correction directe sur `main` (contourne la CI).

**Limites** : sur un dépôt privé avec un compte GitHub gratuit, les règles 
de protection de branche ne sont pas appliquées, donc une PR rouge reste 
fusionnable. Une règle exigeant les checks verts sera activée au passage 
du dépôt en public.

## ADR-35 — Source externe mensuelle non bloquante

**Contexte** : le DAG leclerc_daily a échoué sur la tâche extract_insee parce que l'API INSEE (bdm.insee.fr) renvoyait une erreur 500 côté serveur. Comme extract_insee précédait dbt_build_silver, cette panne extérieure bloquait toute la reconstruction quotidienne de Silver et Gold, alors que l'IPC n'est publié qu'une fois par mois. Par ailleurs, l'appel requests n'avait pas de timeout et pouvait rester bloqué indéfiniment.

**Décision** : extract_insee reçoit 3 relances avec retry_exponential_backoff=True et un délai de départ de 5 minutes (environ 5, 10 puis 20 minutes), pour absorber une panne passagère. dbt_build_silver passe en trigger_rule="all_done" : il démarre une fois extract_insee terminé, quel que soit son état, et Silver et Gold sont reconstruits avec le dernier indice INSEE déjà chargé dans Bronze. La table Bronze n'est pas touchée en cas d'échec, car l'appel à l'API a lieu avant le CREATE OR REPLACE TABLE. L'appel requests a désormais un timeout de 30 secondes. L'alerte Slack de l'ADR-34 continue de signaler l'échec d'extract_insee après la dernière relance. Un test pytest vérifie les relances et le trigger_rule.

**Alternatives écartées** : sortir extract_insee du DAG quotidien dans un DAG mensuel, plus juste sur le fond mais qui ajoute un second DAG à maintenir pour une seule source ; un trigger_rule="none_failed", qui bloquerait Silver comme aujourd'hui ; une tâche qui avale l'erreur, qui masquerait la panne au lieu de la signaler.

**Limites** : all_done laisse aussi passer un extract_insee en échec pour une autre raison qu'une panne INSEE (bug dans le script, identifiants Snowflake), seule l'alerte Slack le révèle. Le run du DAG apparaît en succès dans Airflow dès qu'export_gold réussit, même si extract_insee a échoué. Les relances retardent Silver et Gold d'environ 35 minutes au pire. Si l'indice d'un nouveau mois n'a pas pu être chargé, les marts restent sur le mois précédent jusqu'au prochain run réussi.
## ADR-36 — Modèle sémantique Power BI en étoile

**Date** : 2026-10-19
**Statut** : acceptée

**Contexte.** Les tables Gold sont exportées en CSV et chargées dans Power BI. Sans modèle, chaque visuel dépend d'une table isolée, les filtres ne se propagent pas d'une table à l'autre et les mêmes calculs sont refaits à plusieurs endroits.

**Décision.** Un modèle en étoile :
- une table de dates `Dates` générée en DAX (`CALENDAR` sur septembre 2025 → septembre 2026), avec mois, début de mois et jour de semaine ;
- deux dimensions : `Rayons` (29 rayons) et `Segments` (5 segments RFM) ;
- des relations 1:* à sens unique : `Dates[Date]` vers `mart_kpis_mois[MOIS]`, `mart_kpis_mois_rayon[MOIS]` et `mart_tendances_jour[JOUR]` ; `Rayons[RAYON]` vers `mart_kpis_mois_rayon[RAYON]` ; `Segments[SEGMENT]` vers `mart_rfm_customers[SEGMENT]` ;
- toutes les mesures regroupées dans une table `_Mesures`.

Les tables `mart_mba_paniers` et `mart_mba_regles` restent sans relation : elles portent sur des paires de rayons calculées sur toute la période et ne dépendent ni d'une date ni d'un client.

**Alternatives écartées.**
- Relier directement les tables de faits entre elles : relations plusieurs-à-plusieurs, résultats ambigus.
- Relations bidirectionnelles : plus simples à première vue, mais elles créent des chemins de filtre multiples et des totaux difficiles à expliquer.
- Utiliser `Dates[Mois]` (texte) comme clé : il faut relier sur une vraie date pour que les fonctions de temps (`PREVIOUSMONTH`) fonctionnent.

**Limites.** La table `Dates` a des bornes fixes. Si le pipeline produit des données au-delà de septembre 2026, il faudra étendre `CALENDAR`, ou le remplacer par des bornes calculées (`MIN`/`MAX` des dates de faits).

---

## ADR-37 — Masquer les mois incomplets dans une mesure

**Date** : 2026-10-19
**Statut** : acceptée

**Contexte.** Le dernier mois des données (septembre 2026) n'est que partiellement couvert. Affiché tel quel, il donne l'impression d'un effondrement des ventes : Boissons passe de 206 K€ en août à 124 K€ en septembre.

**Décision.** La mesure `CA rayon mois complet` compare le nombre de jours couverts par les données (`Jours couverts`) au nombre de jours du mois (`DAY ( EOMONTH ( … ) )`) et renvoie une valeur vide si le mois n'est pas complet. Les visuels masquent alors automatiquement la colonne. Les mesures `Dernier mois complet` et `Croissance 6 mois` s'appuient sur la même règle.

**Alternatives écartées.**
- Décocher septembre dans un filtre de visuel : à refaire à chaque nouveau mois, et facile à oublier.
- Exclure le mois en amont dans dbt : on perdrait une information utile au pilotage quotidien (page Tendances).

**Limites.** La règle suppose qu'un mois complet a une vente chaque jour. Un jour de fermeture (1er mai, 25 décembre) ferait passer un mois réel pour incomplet ; il faudrait alors comparer à un calendrier d'ouverture plutôt qu'au nombre de jours calendaires.

---

## ADR-38 — La médiane comme référence entre rayons

**Date** : 2026-10-19
**Statut** : acceptée

**Contexte.** La page Rayons compare un rayon sélectionné à une référence. Le CA par rayon est très déséquilibré : Viandes/charcuterie fait environ 1,25 M€ par mois, les autres rayons au plus 230 K€. La moyenne (environ 92 K€) est tirée vers le haut par ce seul rayon, et presque tous les rayons apparaissent « sous la moyenne ».

**Décision.** La référence est la médiane des rayons (`MEDIANX ( ALL ( Rayons[RAYON] ), … )`), qui représente un rayon typique. Pour la même raison, le dégradé de couleur de la matrice rayons × mois a un maximum fixé à 250 000 € au lieu de la valeur la plus haute, sinon tous les rayons sauf Viandes seraient presque blancs.

**Alternatives écartées.**
- La moyenne : trompeuse avec une distribution aussi asymétrique.
- Exclure Viandes du calcul : arbitraire, et à justifier rayon par rayon.

**Limites.** La médiane ne réagit pas aux écarts extrêmes ; elle ne dit pas de combien les gros rayons dominent. Cette information reste visible dans la matrice et dans le KPI « Part du top 3 ».

---

## ADR-39 — Afficher les extrêmes plutôt qu'un simple classement

**Date** : 2026-10-19
**Statut** : acceptée

**Contexte.** Sur les graphiques d'écart à la moyenne (page Vue d'ensemble) et de croissance sur 6 mois (page Rayons), un « Top 8 » trié par ordre décroissant ne montrait que des rayons en progression. Les rayons qui décrochent, les plus utiles pour un responsable, n'apparaissaient jamais.

**Décision.** Des mesures `Écart extrêmes` et `Croissance extrêmes` classent les rayons deux fois avec `RANKX`, du meilleur au pire puis du pire au meilleur, et ne gardent que les 4 premiers de chaque classement. Les barres sont colorées en vert ou en rouge selon le signe, par une mesure de couleur.

**Alternatives écartées.**
- Afficher les 29 rayons : illisible dans l'espace disponible.
- Deux visuels séparés (top et flop) : double l'espace pour la même information.

**Limites.** S'il y a moins de 8 rayons avec des données, les deux classements se recoupent et le graphique affiche moins de 8 barres, ce qui est le comportement attendu.

---

## ADR-40 — Pas de filtre de mois sur les pages Clients RFM et Panier

**Date** : 2026-10-19
**Statut** : acceptée

**Contexte.** Le cadre de page (menu, titre, segment de mois) a été copié sur toutes les pages. Or `mart_rfm_customers` est un instantané calculé sur toute la période, et les règles d'association sont calculées sur l'ensemble des paniers : ces tables ne sont pas reliées à `Dates`.

**Décision.** Le segment de mois n'existe que sur les pages Vue d'ensemble et Rayons, où il est synchronisé. La page Clients RFM a un segment par segment de clients ; la page Panier n'a pas de filtre de date. Sur la page Rayons, les KPI portent sur le dernier mois complet, affiché en toutes lettres.

**Alternatives écartées.**
- Un segment de mois synchronisé sur toutes les pages : il afficherait « août 2026 » sur des chiffres qui portent sur toute l'année, et l'utilisateur croirait filtrer sans que rien ne change.

**Limites.** On ne peut pas suivre l'évolution d'un segment RFM dans le temps. Il faudrait historiser la segmentation dans dbt, par exemple avec un snapshot mensuel.

---

## ADR-41 — Libellés de segments ajoutés dans Power BI, valeurs dbt inchangées

**Date** : 2026-10-19
**Statut** : acceptée

**Contexte.** Les segments RFM produits par dbt sont nommés par volume et par activité (« Achats nombreux, actifs », « Achats moyens, partis »…), conformément à la limite connue du générateur de transactions. Ces noms sont longs à l'affichage. Les mesures `Part Champions`, `Part à risque` et `Part CA Champions` filtrent sur ces valeurs exactes : elles renvoyaient d'abord une valeur vide parce qu'elles cherchaient « Champions » et « À risque », qui n'existent pas.

**Décision.** Une colonne calculée `Segments[Libellé]` (`SWITCH`) donne un nom d'affichage plus court à chaque segment (« Gros acheteurs actifs », « Clients moyens partis »…). Les visuels utilisent `Libellé` ; les mesures et la couleur des barres continuent de filtrer sur `SEGMENT`. La dernière branche du `SWITCH` renvoie le nom d'origine si un nouveau segment apparaît.

**Alternatives écartées.**
- Renommer les valeurs dans Power Query ou dans la table : casse les mesures qui filtrent sur le texte et rompt la correspondance avec dbt et la documentation.
- Renommer les segments dans dbt avec des étiquettes marketing (« Champions ») : contredit la décision de nommer les groupes par volume, faute de données réelles pour justifier ces profils.

**Limites.** Les noms de segments sont écrits en dur dans quatre mesures et dans la colonne de libellé. Un changement de nom côté dbt doit être répercuté à la main dans Power BI ; une table de correspondance produite par dbt (seed) supprimerait cette double saisie.

---

## ADR-42 — Définition du segment « à risque »

**Date** : 2026-10-19
**Statut** : acceptée

**Contexte.** La page Clients RFM met en avant les clients à risque. Deux segments pouvaient prétendre à ce rôle : « Achats faibles, actifs » et « Achats moyens, partis ».

**Décision.** Le segment à risque est « Achats moyens, partis » (environ 6 % des clients, 88 jours sans achat en moyenne, 1 276 € dépensés). En RFM, le risque désigne des clients qui avaient de la valeur et dont la récence se dégrade : ce sont eux qu'une relance peut faire revenir. « Achats faibles, actifs » sont des clients présents mais peu dépensiers, à développer plutôt qu'à retenir. « Achats faibles, partis » (224 jours sans achat) sont considérés comme perdus.

**Alternatives écartées.**
- « Achats faibles, actifs » : ces clients reviennent régulièrement, il n'y a pas de risque de départ à traiter.
- Regrouper les deux segments « partis » : mélange des clients récupérables et des clients perdus, et dilue la cible d'une éventuelle campagne.

**Limites.** Les segments reposent sur des seuils fixés dans dbt et sur des transactions synthétiques. Sur des données réelles, il faudrait valider ces seuils avec les équipes marketing et suivre le taux de retour des clients relancés.

---

## ADR-43 — Règles d'association : un seul sens pour le classement par lift

**Date** : 2026-10-19
**Statut** : acceptée

**Contexte.** `mart_mba_regles` contient 342 règles, c'est-à-dire 171 paires de rayons dans les deux sens (A → B et B → A). La confiance dépend du sens, mais le lift est symétrique. Un « Top 8 par lift » affichait donc chaque paire deux fois, soit 4 paires seulement, et le KPI « Paires fortes » comptait chaque paire en double (62 au lieu de 31).

**Décision.** Une colonne calculée `Sens unique` vaut 1 quand `ITEM_A < ITEM_B` (ordre alphabétique). Le classement par lift et le KPI « Paires fortes » ne gardent que ces lignes. Le tableau des règles et le nuage support × confiance gardent les deux sens, puisque la confiance y est l'information utile. Les règles sont classées en quatre niveaux de force (lift ≥ 10, ≥ 3, ≥ 1,5, en dessous), avec une couleur par niveau et un segment pour filtrer la page.

**Alternatives écartées.**
- Dédoublonner dans dbt : on perdrait la confiance dans le second sens.
- Filtrer sur la confiance la plus haute des deux sens : plus complexe, sans gain de lecture.

**Limites.** Les lifts observés (jusqu'à 19) sont très supérieurs à ceux d'un vrai supermarché (1,5 à 3 en général). Ils reflètent les associations intégrées dans le générateur de transactions, pas un comportement d'achat réel.

---

## ADR-44 — Page Tendances : exclusion d'une semaine anormale et comparaison en base 100

**Date** : 2026-10-19
**Statut** : acceptée

**Contexte.** Deux problèmes sont apparus sur la page Tendances.
1. Du 23 au 28 septembre 2025, le CA journalier dépasse 100 K€, contre environ 35 K€ les semaines suivantes. Cette semaine correspond au démarrage du générateur de transactions. Elle faussait la moyenne par jour de semaine (le « meilleur jour » sortait mardi à cause d'un seul mardi exceptionnel) et la base de comparaison.
2. Le graphique ventes / IPC utilisait deux axes. Power BI étirait chaque axe séparément : une hausse de l'IPC d'environ 1,5 % paraissait aussi forte qu'une hausse du CA de près de 190 %, et le graphique suggérait à tort que l'inflation expliquait les ventes.

**Décision.**
1. Un filtre de page exclut toutes les dates jusqu'au 30 septembre 2025. La page commence au 1er octobre, premier mois complet sans anomalie.
2. Les deux séries sont ramenées en base 100 sur le premier mois affiché (`CA indice`, `IPC indice`, calculés avec `ALLSELECTED` pour suivre le segment de dates) et tracées sur un seul axe. Le sous-titre rappelle que les prix simulés ne dépendent pas de la date.

Un tableau de diagnostic temporaire (IPC moyen, minimum et maximum par mois) a confirmé que les données INSEE étaient saines (une valeur par mois, de 100,4 à 101,8) et que l'écart venait du double axe.

**Alternatives écartées.**
- Garder le double axe en fixant les bornes à la main : à refaire si les données changent, et toujours trompeur à la lecture.
- Corriger l'anomalie dans Power BI sur toutes les pages : le problème vient de l'amont.

**Limites.** Le filtre ne corrige que la page Tendances. La correction durable se trouve en amont : corriger le démarrage du générateur, et ajouter un test dbt qui signale un jour dont le CA s'écarte fortement de la moyenne mobile. Le « meilleur jour » restant (lundi) ne se distingue des autres que de peu : avec des données simulées, le jour de la semaine n'a presque pas d'effet.

---

## ADR-45 — CI sans entrepôt et contrôles obligatoires sur `main`

**Date** : 2026-10-21
**Statut** : acceptée (remplace en partie la CI dbt décrite plus haut)

**Contexte.** L'essai Snowflake s'est terminé le 20 octobre 2026. Le workflow `dbt-ci.yml` lançait `dbt debug` puis `dbt build` dans le schéma `CI_PR` : il a échoué sur la PR #10, qui ne touchait pourtant pas dbt, et le dépôt, désormais public, affichait une croix rouge. La PR #10 a été fusionnée malgré cet échec, comme la PR #6 avant elle (ADR-34) : la protection de `main` n'exigeait pas que les contrôles passent. Une CI qui n'est pas bloquante n'est qu'un avis.

**Décision.**
- `dbt-ci.yml` remplace `dbt debug` et `dbt build` par `dbt parse`, avec la cible `ci` et des valeurs factices pour les variables du profil. `dbt parse` ne se connecte jamais à l'entrepôt : il valide le Jinja, les `ref()` et `source()`, les fichiers YAML et les tests déclarés. Les anciennes étapes restent en commentaire dans le fichier, avec la marche à suivre pour les réactiver.
- Les deux workflows (`dbt-ci.yml` et `airflow-ci.yml`) tournent sur toutes les pull requests vers `main`, sans filtre de chemins.
- Un ruleset GitHub protège `main` : pull request obligatoire (0 approbation, projet mené seul), contrôles `dbt-parse` et `dag-tests` obligatoires, force push et suppression interdits, liste de contournement vide. Un push direct sur `main` a été testé et refusé (`GH013: Repository rule violations`).
- Les actions passent à `actions/checkout@v5` et `actions/setup-python@v6` (fin de Node.js 20), et le runner est fixé sur `ubuntu-24.04` au lieu de `ubuntu-latest`.

**Alternatives écartées.**
- Désactiver le workflow dbt : plus de croix rouge, mais plus aucune preuve.
- Faire tourner dbt sur DuckDB ou PostgreSQL pendant la CI : on exécuterait le SQL, mais certaines fonctions sont propres à Snowflake. Il faudrait maintenir deux dialectes pour un seul projet.
- Garder les filtres de chemins : un contrôle obligatoire qui ne se lance pas reste « en attente » pour toujours, et bloque les pull requests qui ne touchent pas dbt (Power BI, documentation).
- Ouvrir un nouvel essai Snowflake : la CI recasserait 30 jours plus tard.

**Limites.** `dbt parse` ne vérifie pas que le SQL s'exécute, ni que les 33 tests de données passent. Avec un compte Snowflake actif, il faut remettre les secrets et réactiver `dbt build`. Le schéma `CI_PR` porte un nom fixe : deux pull requests simultanées y écriraient en même temps. En équipe, il faudrait un schéma par pull request (par exemple `CI_PR_<numéro>`).
