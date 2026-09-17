# Installer et mettre à jour LocalWriter

LocalWriter comprend une app de barre de menus pour les éditeurs macOS et une extension Chrome pour les pages web, dont Google Docs. Les deux utilisent Qwen3 4B sur le Mac. Le modèle traite les textes en anglais.

## Prérequis

- macOS 14 ou plus récent ; Mac Apple Silicon recommandé. Le M3 avec 32 Go convient à cette configuration.
- Git, Python 3 et les outils de compilation Apple (`xcode-select --install` si nécessaire).
- Google Chrome pour l’extension.
- Accès au dépôt GitHub privé. Node.js est facultatif, pour les tests JavaScript.
- [Ollama pour macOS](https://ollama.com/download/mac), installé et lancé. Le premier téléchargement du modèle nécessite Internet.

## 1. Récupérer le dépôt

```sh
git clone git@github.com:johnBgood/local-writing-assistant.git
cd local-writing-assistant
```

Toutes les commandes suivantes sont à exécuter depuis ce dossier. Sur le Mac de développement actuel, le dépôt se trouve dans `/Users/jonathanroques/Documents/ChatGPT/Grammarly`.

## 2. Installer et démarrer le modèle local

Après avoir lancé Ollama :

```sh
scripts/setup-model.sh
```

Ce script télécharge `qwen3:4b`. Pour démarrer le serveur en terminal, si Ollama ne tourne pas déjà :

```sh
scripts/start-model.sh
```

Garder ce terminal ouvert. Ne pas démarrer deux serveurs sur le même port. Le serveur attendu est `http://127.0.0.1:11434`.

Le poste de développement possède aussi un runtime et des poids dans `.local-runtime/`. Ils ne sont **pas inclus dans Git**. Sur ce poste, l’app peut démarrer ce runtime via **Start Local Model**. Sur un nouveau Mac, utiliser l’installation Ollama ci-dessus. Garder l’app dans `dist/` pour qu’elle retrouve le runtime du projet.

## 3. Construire et lancer l’app Mac

```sh
scripts/build-app.sh
open dist/LocalWriter.app
```

LocalWriter apparaît dans la barre de menus avec l’icône **✎**. Il n’y a pas encore d’installation automatique dans Applications ni de lancement automatique à l’ouverture de session.

Dans le menu LocalWriter, choisir **Grant Accessibility Access…**, puis autoriser **LocalWriter** dans **Réglages Système → Confidentialité et sécurité → Accessibilité**. Cette permission sert à lire les éditeurs des apps natives et à appliquer les corrections. Le pont Chrome utilise un mécanisme distinct.

Pour tester sans permission d’accessibilité :

```sh
open dist/LocalWriter.app --args --practice
```

Dans l’éditeur de test, saisir `This is a speling mistake.`, attendre l’analyse, puis accepter la suggestion. Dans Slack ou Notes, laisser le texte non envoyé, placer le curseur dans l’éditeur et attendre. Le menu **Enable for … / Disable for …** contrôle l’app concernée. **Editor Diagnostics…** indique notamment l’état de la permission.

### Signature et permission après recompilation

Ce poste utilise une identité de signature locale stable. Elle est privée, stockée dans `.local-signing/` et absente de Git. Un nouveau clone utilise par défaut une signature ad hoc : une recompilation peut rendre l’ancienne permission d’accessibilité invalide.

Pour créer volontairement une identité locale stable sur un nouveau poste, après la première compilation :

```sh
python3 scripts/sign-app.py dist/LocalWriter.app --setup
scripts/build-app.sh
```

Cette étape crée un certificat et un trousseau locaux ; elle n’ajoute pas de certificat racine de confiance. Autoriser ensuite la version finale de l’app. Si les diagnostics indiquent une permission absente malgré la case cochée, quitter LocalWriter, retirer son ancienne entrée dans Accessibilité et ajouter la version actuelle de `dist/LocalWriter.app`. Ne pas réinitialiser les autorisations à chaque mise à jour.

## 4. Installer le pont Chrome

Après compilation de l’app :

```sh
python3 scripts/install-extension-host.py
```

Ce script installe :

- Le pont et son lanceur dans `~/Library/Application Support/LocalWriter/NativeMessaging/`.
- Sa déclaration Chrome dans `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.johnbgood.localwriter.json`.

Seule l’extension LocalWriter, d’identifiant `pkcahnmnafkepdcfepmbnboaadnbkhnl`, est autorisée à lancer ce pont. Ne pas déplacer le pont dans Documents : son lancement par Chrome y a échoué sur le poste de développement. Aucun port réseau supplémentaire n’est ouvert.

## 5. Charger l’extension Chrome

1. Ouvrir `chrome://extensions`.
2. Activer **Mode développeur**.
3. Cliquer sur **Charger l’extension non empaquetée / Load unpacked**.
4. Sélectionner le dossier **extension** du dépôt, pas la racine du projet.
5. Ouvrir **LocalWriter** depuis le menu Extensions de Chrome et, si souhaité, l’épingler.
6. Vérifier **Connected to LocalWriter on your Mac**.
7. Utiliser **Open practice editors** pour tester une correction et son remplacement.

Le modèle doit rester en fonctionnement. Dans le menu de l’app Mac, choisir **Disable for Google Chrome** pour éviter les doubles soulignements avec l’extension. Les autres apps restent disponibles.

## 6. Utiliser Google Docs

1. Ouvrir le document.
2. Ouvrir le popup LocalWriter et cliquer sur **Enable underlines on this tab**.
3. Fermer le popup et attendre l’analyse.
4. Cliquer sur un soulignement puis sur la correction pour l’accepter.
5. Sélectionner une phrase, avec la souris ou le clavier, et patienter pour voir sa reformulation. Cliquer sur la carte pour remplacer la sélection entière.

L’activation vaut pour l’onglet jusqu’à son actualisation. Après actualisation, il faut réactiver LocalWriter. L’adaptateur Google Docs est expérimental : il analyse le texte visible, jusqu’à 4 000 unités UTF-16. Une sélection répétée ou partiellement hors écran peut être refusée pour éviter de modifier le mauvais passage. Si les annotations de texte de Docs sont absentes, utiliser la vérification de sélection dans le popup avec copie manuelle.

## 7. Mettre à jour sans conserver d’ancien script

Après avoir quitté LocalWriter depuis son menu :

```sh
git pull --ff-only
scripts/build-app.sh
python3 scripts/install-extension-host.py
open dist/LocalWriter.app
```

Puis dans Chrome :

1. Aller dans `chrome://extensions` et cliquer sur **Recharger sur la carte LocalWriter**.
2. Vérifier la version affichée sur cette carte.
3. **Actualiser aussi le Google Doc ou la page web** : recharger l’extension seul ne retire pas nécessairement le script déjà injecté dans l’onglet.
4. Réouvrir le popup LocalWriter et réactiver **Enable underlines on this tab**.

Si seuls les fichiers de l’extension ont changé, la recompilation Swift et la réinstallation du pont ne sont pas nécessaires. Si l’app ou le pont a changé, relancer le script d’installation : Chrome utilise une copie installée du binaire.

## Dépannage

| Symptôme | Vérification |
| --- | --- |
| `Native host has exited` ou connexion impossible | Relancer `python3 scripts/install-extension-host.py`, vérifier que la compilation existe et que le pont est installé dans Application Support. |
| Modèle indisponible | Lancer Ollama ou `scripts/start-model.sh`, puis vérifier que `scripts/setup-model.sh` a téléchargé Qwen3 4B. |
| Rien après une mise à jour | Recharger **LocalWriter**, actualiser la page, puis réactiver les underlines. |
| Permission cochée mais diagnostics négatifs | Vérifier la signature et l’entrée d’accessibilité de la version actuelle de l’app. |
| Suggestion périmée ou sélection non confirmée | Resélectionner le passage sans modifier le document pendant l’analyse. Le remplacement est bloqué si la sélection ne correspond plus. |
| Plusieurs cartes ou soulignements concurrents | Désactiver LocalWriter natif pour Chrome et vérifier les autres correcteurs actifs dans ce document. |

Tests facultatifs depuis la racine :

```sh
scripts/check.sh
node scripts/check-extension.mjs
python3 scripts/check-extension.py
```

Le dernier test utilise le pont installé et le modèle réel. Ces tests ne remplacent pas un essai visuel dans l’éditeur concerné.

## Désinstaller

Quitter LocalWriter et retirer son entrée d’accessibilité si souhaité. Supprimer l’extension dans `chrome://extensions`, puis supprimer uniquement la déclaration `com.johnbgood.localwriter.json` et le dossier `~/Library/Application Support/LocalWriter/NativeMessaging/` indiqués plus haut. Les modèles Ollama et le dépôt restent sur disque tant qu’ils ne sont pas supprimés séparément.
