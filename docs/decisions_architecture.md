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
