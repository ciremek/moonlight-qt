# Spike : interface SwiftUI hybride

Date : 17 octobre 2026 · Branche : `spike-swiftui` · Statut : **validé**

## Question

Peut-on remplacer l'interface QML (Material) de moonlight-qt par une interface
SwiftUI native (Liquid Glass) sans réécrire le moteur ?

## Constat de départ

Le « moteur » ne se limite pas à moonlight-common-c. La découverte des PC
(mDNS), l'appairage, le HTTP vers Sunshine, les réglages et la session de
stream sont tous en Qt (`ComputerManager`, `NvHTTP`, `QSettings`, `Session`).
Une coquille SwiftUI « pure » obligerait à tout réécrire.

## Approche retenue : hybride

- Qt reste l'hôte du processus et garde tout le backend, sans modification.
- L'interface est une fenêtre AppKit qui héberge du SwiftUI
  (`NSHostingController`), compilée par `swiftc` en `libMoonvibeUI.dylib`
  depuis `app/app.pro`.
- Le pont est une API C minimale (`app/swiftui/moonvibeui.h`) :
  - Qt → Swift : `mv_ui_show`, `mv_ui_update_computers` (JSON),
    `mv_ui_set_status`, `mv_ui_set_visible` ;
  - Swift → Qt : callbacks C `launch(uuid, appId)` et `quit()`.
- `SwiftUIShell` (C++) alimente la fenêtre depuis `ComputerManager` et pilote
  `Session` comme le faisait `StreamSegue.qml`. La fenêtre de stream SDL ne
  change pas.
- `MOONVIBE_QML=1` relance l'ancienne interface QML.

## Résultats

- Liste des PC et des apps à jour en direct (statut en ligne, appairage).
- Lancement et reprise d'un stream depuis la fenêtre SwiftUI, retour à la
  fenêtre après ⌃⌥⇧Q, relancement possible ensuite.
- Résolution auto et coupure AWDL fonctionnent à l'identique.
- Bouton principal en `.glassProminent` sur macOS 26+, repli sur
  `.borderedProminent` avant.

## Décision

On part sur l'**option 2 en hybride** pour la refonte Liquid Glass.

## Points à traiter pendant la refonte

- `Session::initialize()` reçoit `nullptr` comme fenêtre Qt : la résolution
  auto et le placement de la fenêtre de stream se rabattent sur l'écran
  principal. Il faudra passer l'écran de la fenêtre SwiftUI.
- Les textes de statut du pont sont encore des chaînes `tr()` anglaises du
  contexte C++ : à traduire ou à déplacer côté Swift.
- Pas encore d'appairage, de réglages, de gestion manette (navigation de
  l'UI au gamepad) ni d'écran de quit/erreur dédié.
- Le build Swift cible arm64 uniquement, comme le reste du build local.
