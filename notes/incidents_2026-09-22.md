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
