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
