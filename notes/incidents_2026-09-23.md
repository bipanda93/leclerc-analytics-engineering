# Incidents — 2026-09-23

## pytrends archivé — pivot vers INSEE
Recherche préalable au codage a révélé que le dépôt GitHub de pytrends est 
archivé depuis le 17 avril 2025, non maintenu, avec un comportement de 
rate-limiting imprévisible en 2026 (erreur "trop de requêtes" parfois dès 
le premier appel). Décision : abandon de Google Trends avant même d'écrire 
une ligne de code, remplacé par l'API SDMX gratuite de l'INSEE (voir 
ADR-17).

## Mauvais idbank sur la première tentative INSEE
Le premier idbank essayé (récupéré depuis l'URL de la page insee.fr) a 
renvoyé une erreur SDMX "Aucun résultat ne correspond à cette requête" — 
l'identifiant affiché dans l'URL de la page n'est pas toujours le vrai 
idbank technique attendu par le service SDMX. Fix : idbank retrouvé 
directement sur la page officielle de métadonnées de la série 
(insee.fr/fr/metadonnees/source/indicateur/...), affiché explicitement.

## Confusion ordre des définitions Python (deux fois)
Dans `insee_conjoncture_extract.py` : une fonction 
(`build_insee_dataframe`) placée après le bloc `if __name__ == 
"__main__":` qui l'utilisait — en Python, une fonction doit être définie 
avant d'être appelée, l'exécution se fait de haut en bas. Fix : 
réorganisation du fichier, toutes les fonctions avant le bloc 
d'orchestration final.

## Boucle dupliquée au lieu de continuée
Dans la même ébauche, une deuxième boucle `for` (sur une variable `data` 
inexistante) a été ajoutée pour "terminer" une première boucle déjà en 
cours (`for obs in root.findall(...)`), au lieu de continuer le traitement 
à l'intérieur de la boucle existante. Fix : fusion en une seule boucle, du 
parsing XML jusqu'à la construction du dictionnaire final.

## ModuleNotFoundError sur l'import du module partagé
`from ingestion.snowflake_utils import ...` échoue avec 
`ModuleNotFoundError: No module named 'ingestion'` quand le script est 
lancé depuis l'intérieur de `ingestion/` — Python ajoute le dossier du 
script exécuté à son chemin de recherche, pas la racine du repo. Fix : 
import relatif simple (`from snowflake_utils import ...`), sans préfixe de 
dossier, puisque les deux fichiers sont dans le même répertoire. Appliqué 
aussi rétroactivement à `transactions_generator.py` pour cohérence.

## SyntaxError sur une chaîne de caractères (snowflake_utils.py)
Apostrophes probablement altérées lors d'un copier-coller (apostrophe 
"intelligente" au lieu d'une apostrophe simple), causant une chaîne non 
terminée dans un message d'erreur f-string. Fix : retaper la ligne 
directement dans l'éditeur plutôt que coller.

## Confusion emplacement dossier dbt init
`dbt init leclerc_dbt` lancé depuis `~/leclerc-analytics-engineering/leclerc_dbt/` (dossier déjà existant portant ce nom) plutôt que depuis `~/leclerc-analytics-engineering/dbt/` — a créé une double imbrication (`leclerc_dbt/leclerc_dbt/`). Un vieux dossier vide `dbt/leclerc_dbt/` (placeholder de l'arborescence initiale du 16 septembre, jamais rempli) a ajouté à la confusion lors du diagnostic. Fix : `find -name dbt_project.yml` pour localiser sans ambiguïté le vrai projet, suppression du placeholder vide, déplacement du vrai projet vers `dbt/leclerc_dbt/`. `dbt debug` relancé et validé après coup.

## RBAC Bronze/Silver incomplet lors de la mise en place initiale
ACCOUNTADMIN n'avait accès ni à OPEN_PRICES ni à TRANSACTIONS (créées par LECLERC_AIRBYTE_LOADER, propriétaire par défaut), reproduisant l'incident déjà documenté le 22 septembre — Snowflake n'accorde jamais d'accès automatique aux objets créés par un autre rôle, même à ACCOUNTADMIN. Fix cette fois plus large et définitif : GRANT SELECT ON FUTURE TABLES/VIEWS IN SCHEMA posé sur BRONZE et sur SILVER, couvrant tout objet futur peu importe le rôle créateur.

## Confusions terminal répétées sur --select
Plusieurs tentatives infructueuses pour lancer un modèle dbt ciblé : nom de fichier avec extension .sql ajoutée par erreur (--select attend le nom du modèle, pas le nom de fichier), puis un seul underscore tapé au lieu de deux dans stg_insee__conjoncture (convention stg_<source>__<entité>). dbt échoue silencieusement dans ce cas (aucune erreur, juste "no matching nodes") — à bien distinguer d'un vrai échec de modèle.

## Erreurs de syntaxe SQL répétées en testant dans Snowsight
Requêtes de vérification manuelle : confusion guillemets simples/doubles ('valeur' vs "identifiant"), requête collée en dessous d'une précédente sans effacer (deux requêtes lues comme un seul bloc invalide), et Object 'CLEANED' does not exist quand seule la partie finale d'un CTE est sélectionnée avant exécution — toujours nécessaire de sélectionner tout le bloc (Cmd+A) avant de lancer dans Snowsight.
