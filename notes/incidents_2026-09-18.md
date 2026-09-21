# Incidents — 2026-09-18

## Homebrew : tap non approuvé
`brew install airbytehq/tap/abctl` refusé (protection anti-supply-chain 
2026).
Fix : `brew trust --formula airbytehq/tap/abctl`.

## Airbyte CHECK pod — ResourceConstraintException
Échec de scheduling Kubernetes après un pull d'images de 40+ min. Docker 
Desktop
s'est retrouvé dans un état instable (le daemon a fini par ne plus 
répondre du tout).
Fix : redémarrage complet de Docker Desktop, puis `abctl local uninstall` 
+ `abctl local install`.

## Login Airbyte bloqué (cookies sécurisés sur HTTP)
Safari refuse les cookies `Secure` sur localhost, contrairement à 
Chrome/Firefox qui ont
une exception dédiée. Fix définitif : `abctl local install 
--insecure-cookies`.
Contournement immédiat : utiliser Chrome.

## Discovery Open Food Facts — CSV mal formé
`pandas.errors.ParserError: Expected 52 fields in line 3, saw 95` — 
tabulation littérale
non échappée dans un champ texte (millions de contributions utilisateur).
Fix Reader Options : `{"sep": "\t", "compression": "gzip", "on_bad_lines": 
"skip", "dtype": "str"}`.

## Sync Open Prices — Timestamp non sérialisable en JSON
`Object of type Timestamp is not JSON serializable` — colonnes 
`date`/`proof_date` typées
natif timestamp dans le Parquet, bug du connecteur `source-file:0.6.0` 
(dernière version
disponible, pas de fix en amont). Fix Reader Options : `columns` explicite 
excluant les deux
champs timestamp ; `created`/`updated` (string) gardés comme substituts 
pour l'analyse temporelle.

## Repo git accidentel à la racine du home
`~` s'est retrouvé être un repo git (jamais poussé, contenu limité à 
mini_airflow).
Isolé proprement : `mini_airflow` et `nosql-benchmarking` déplacés vers 
leurs propres repos dédiés.

## Mots de passe RBAC exposés dans un commit local
`rbac_roles.sql` commité avec les mots de passe des comptes de service en 
clair.
Rotation immédiate (`ALTER USER ... SET PASSWORD`), Airbyte mis à jour, 
fichier amendé
avec des placeholders avant tout push.

