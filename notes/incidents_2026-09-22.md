# Incidents — 2026-09-22

## Confusion .env / .env.example
Les vraies valeurs (compte, mot de passe) collées par erreur dans 
`.env.example` — le fichier modèle, destiné à être commité. Corrigé en 
séparant clairement les deux fichiers : `.env.example` remis à des valeurs 
vides, vraies valeurs déplacées vers `.env` (ignoré par git, déjà 
confirmé).

## pip install parti dans le mauvais environnement conda
`pip install -r requirements.txt` lancé depuis `(base)` au lieu de 
`(leclerc)` — conflits de dépendances révélés avec d'autres projets 
(Airflow, mlflow, ravendb, tensorflow) déjà installés dans `base`. Aucun 
dégât sur les environnements nommés (`leclerc`, `dbt_env`, `ml_env`...), 
isolés du système de fichiers de `base`. Fix : `conda activate leclerc` 
avant de relancer l'install — déjà satisfaite, rien de cassé.

## Confusion `os.getenv()` — nom vs valeur
Erreur répétée dans `transactions_generator.py` : les vraies valeurs 
(compte Snowflake, rôle, mot de passe) tapées directement dans 
`os.getenv("...")` et dans `connect(...)`, au lieu du nom de la variable 
d'environnement à chercher. A provoqué en cascade : `NameError` (valeurs 
sans guillemets interprétées comme variables Python inexistantes), puis 
"variables manquantes" (noms de variables d'environnement inexistants 
cherchés). Fix : toujours passer le nom de la clé (`"SNOWFLAKE_ACCOUNT"`) 
à `os.getenv()`, jamais la valeur.

## Mots de passe exposés à plusieurs reprises
Le mot de passe de `LECLERC_AIRBYTE_SVC` collé en clair dans le code 
partagé, à plusieurs reprises, pendant le débogage du point précédent. 
Rotation du mot de passe effectuée après chaque exposition confirmée.

## Champ `code` (code-barres) typé Number par Airbyte
Repéré via une notation scientifique inattendue dans l'aperçu du DataFrame 
(`2.075978e+07`). Confirmé par requête SQL : aucun produit avec un code 
commençant par `0` dans Bronze — les zéros de tête (EAN-13 dérivés 
d'UPC-A) ont été perdus dès l'ingestion, Airbyte ayant inféré le champ 
comme numérique malgré `dtype: str` dans les Reader Options (les deux 
mécanismes ne se coordonnent pas). Non corrigeable a posteriori par un 
simple `CAST`. Décision : documenté comme limite connue (ADR-8), non 
corrigé à la source pour l'instant — voir 
`docs/decisions_architecture.md`.

## Fichier de script corrompu par collage partiel
Un patch donné pour ajouter la logique de prix a été collé avec le `...` littéral de l'exemple (censé signifier "reste inchangé") et a accumulé plusieurs définitions en double (AFFINITY_RULES, build_indexes, generate_basket, generate_transactions, PRICE_RANGES) au fil des itérations. Python n'erreur pas sur les doublons de fonction (la dernière définition écrase silencieusement les précédentes) mais le `...` littéral est une SyntaxError. Fix : régénération complète et consolidée du fichier plutôt qu'un patch de plus.

## Open Prices jamais réellement synchronisé
Après le fix du premier bug Timestamp (date/proof_date exclus), seul un "Refresh" (redétection de schéma, 0 ligne chargée) avait été relancé, jamais un vrai "Sync now". La table LECLERC.BRONZE.OPEN_PRICES n'existait donc pas, provoquant une erreur "Object ... does not exist" côté script Python.

## Deuxième bug Timestamp sur Open Prices (created/updated)
Une fois le vrai sync relancé, le même bug "Object of type Timestamp is not JSON serializable" est réapparu — cette fois sur created/updated (et leurs équivalents proof_*/location_*), malgré leur typage StringType déclaré côté Airbyte. Pod replication-job nettoyé avant capture des logs (fenêtre de récupération trop courte) ; diagnostic fait par hypothèse plutôt que log confirmé : les champs déclarés String par Airbyte ne reflètent pas nécessairement le typage natif réel du fichier Parquet source. Fix : exclusion de tous les champs à consonance temporelle (6 au lieu de 2) via Reader Options — perte assumée de toute temporalité sur Open Prices (voir ADR-14).

## Cast product_code — deux échecs successifs
`.astype("Int64")` échoue avec "cannot safely cast non-equivalent float64 to int64" — pas un NaN classique (dropna n'en a trouvé aucun), plutôt une valeur non-entière après passage en float64. Fix : conversion manuelle avec arrondi explicite et gestion d'erreur, plutôt que la conversion stricte de pandas.

## Casse des colonnes — write_pandas
La table cible créée sans guillemets stocke ses colonnes en majuscules (convention Snowflake par défaut), mais le DataFrame Python garde les siennes en minuscules — write_pandas génère un COPY INTO avec les noms entre guillemets, donc sensible à la casse. Fix : colonnes du DataFrame mises en majuscules juste avant l'écriture.

## ACCOUNTADMIN sans accès à une table qu'il n'a pas créée
Après écriture réussie, un SELECT sur LECLERC.BRONZE.TRANSACTIONS échoue pour ACCOUNTADMIN — la table a été créée par LECLERC_AIRBYTE_LOADER (le script), qui en est propriétaire. ACCOUNTADMIN n'hérite d'aucun accès automatique aux objets créés par un autre rôle. Fix : GRANT SELECT explicite, plus un GRANT ... ON FUTURE TABLES pour couvrir les prochaines recréations (le script fait un CREATE OR REPLACE à chaque run).
