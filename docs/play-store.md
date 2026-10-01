# QxChat — Google Play Store

App ID figé : `com.getqxchat.app` (défini dans `src-tauri/tauri.conf.json`).
Ne plus jamais le changer après la création de la fiche : Play l'interdit.

- Politique de confidentialité (en ligne) : `https://getqxchat.com/privacy`
- Textes FR/EN de la fiche : `fastlane/metadata/android/`

Règle d'or (rappelée par la policy §4) : les déclarations du formulaire
**Data Safety doivent rester identiques** à la page privacy. Si le traitement
des données change, mettre à jour les deux avant rollout.

## 1. Build AAB signé pour Play

Play exige un **`.aab`** (pas l'APK). La signature release utilise déjà
`lqxp-release.jks` (mot de passe via `.env`, voir `docs/BUILD.md` § Android) :

```bash
bun run build:android -- --aab --target aarch64
```

Le `.aab` signé sort sous
`src-tauri/gen/android/app/build/outputs/bundle/universalRelease/`.

Avant chaque upload, vérifier que le `versionCode` a été incrémenté
(`src-tauri/gen/android/app/build.gradle.kts` lit `tauri.android.versionCode`,
`autoIncrementVersionCode` est à `false`) : Play refuse un code déjà envoyé.

## 2. Sécurité des données (recopie de la policy §4)

| Question Play | Réponse |
|---|---|
| Données collectées ? | **Oui** — compte (pseudo + hash Argon2id mot de passe / 12 mots BIP39, sessions SHA-256 TTL 7 j), contenus utilisateur (messages E2EE, photos/vidéo, audio, fichiers), graphe social (membres, rôles, blocages), activité (présence, frappe, participation appels, SDP/ICE relayé non stocké), IDs appareil (client ID aléatoire, version pour update-check). Pas d'email, pas de téléphone, pas d'ID pub, pas de SDK analytics/crash. |
| Données partagées ? | **Non** (ni vente ni partage analytics). Relais fonctionnel uniquement : opérateur du serveur choisi, TURN pour les appels, site cible des link-previews, hôte de mise à jour. |
| Chiffrement en transit ? | **Oui** — HTTPS/WSS + couche E2EE (AES-256-GCM) sur les contenus. |
| Suppression possible ? | **Oui** — `Paramètres → Profil → Supprimer le compte → confirmer → mot de passe`, + demande par email (voir policy §10). |
| Audit de sécurité indépendant ? | Non (code public MIT, pas d'audit tiers commissionné). |

## 3. Justifications des autorisations (recopie de la policy §5)

Toutes demandées **au runtime, en contexte, révocables** ; refuser ne coupe que
la fonction concernée.

- `INTERNET` : connexion au serveur LQXP (WebSocket + HTTPS), uploads/downloads, update-check.
- `CAMERA` : appels vidéo + photos initiées par l'utilisateur. Jamais en arrière-plan.
- `RECORD_AUDIO` + `MODIFY_AUDIO_SETTINGS` : appels vocaux et messages vocaux + routage/écho pendant les appels.
- `POST_NOTIFICATIONS` : notifications **locales** générées on-device. Pas de FCM/APNs.
- `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_DATA_SYNC` : `ForegroundService`
  qui maintient la connexion chiffrée en arrière-plan (sans push tiers).
  Déclaré en `dataSync`.
- `WAKE_LOCK` : empêche l'OS de tuer un appel ou une sync en cours.
- `READ_MEDIA_IMAGES / VIDEO / AUDIO`, `READ_MEDIA_VISUAL_USER_SELECTED`
  (et `READ_EXTERNAL_STORAGE` ≤ API 32) : lecture des seuls fichiers
  **choisis** par l'utilisateur (pièces jointes, avatar/bannière).
- Features caméra/micro déclarées `required="false"` : le chat texte marche sans.

Production = HTTPS/WSS uniquement (cleartext réservé au dev local loopback).

## 4. Points de vigilance console

- **Politique de confidentialité** : `https://getqxchat.com/privacy` ✅ en ligne.
- **Public cible** : policy §12 — app non destinée aux moins de 13 ans.
  Le déclarer tel quel dans le formulaire (pas de programme Familles).
- **Classification du contenu (IARC)** : messagerie avec contenu généré par
  les utilisateurs — répondre honnêtement, catégorie restreinte probable.
- **Compte personnel** : test fermé obligatoire — 12 testeurs minimum pendant
  14 jours avant la production. Préparer la liste d'emails des testeurs.
- **Compte organisation** : numéro D-U-N-S + vérification (plus de test
  fermé imposé, production directe possible après review).
- **Accès reviewers** : compte démo à fournir si un compte est nécessaire
  pour tester (pas d'email/tél requis à l'inscription — le préciser).
- **Premiers visuels** (TODO) : icône 512×512, visuel 1024×500, 2 captures
  téléphone minimum (générer depuis un Pixel / émulateur).
