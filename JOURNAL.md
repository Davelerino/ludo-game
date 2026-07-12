# Journal de bord — Ludo 3D (Godot 4)

Ce fichier raconte, dans l'ordre, comment ce jeu a été construit : les
décisions prises, pourquoi, les bugs rencontrés et comment ils ont été
trouvés. L'objectif est de pouvoir s'en servir plus tard comme trame pour
des vidéos expliquant la création du projet — donc chaque entrée essaie de
répondre à "quel problème on avait" et "pourquoi cette solution-là" plutôt
que de lister des changements de code bruts (ça, c'est dans `git log`).

**Pour continuer ce journal** : ajouter une nouvelle section `## Chapitre N
— <titre>` en bas, avec la date, le problème de départ, la décision prise et
ce qui a été appris. Pas besoin d'un chapitre par petite modif — un chapitre
correspond à un vrai palier (une nouvelle mécanique, une refonte, une
famille de bugs liés).

Dépôt : [Davelerino/ludo-game](https://github.com/Davelerino/ludo-game) —
la PR qui accumule tout ce travail : [#1](https://github.com/Davelerino/ludo-game/pull/1).

---

## Chapitre 1 — Repenser le système de chemin (2026-07-11)

**Le problème.** Le plateau était stocké case par case (des tableaux codés
en dur listant chaque cellule de l'anneau et des couloirs finaux). Difficile
à modifier, aucune structure logique visible dans les données elles-mêmes.

**La décision.** Remplacer ça par une représentation **compacte par
segments** : chaque portion droite du chemin est décrite par une direction,
une longueur et un décalage par rapport au segment précédent — au lieu de
lister 52 cases une par une. Un cache de cellules est reconstruit à la
demande (jamais stocké dans les données sources), ce qui garde le fichier
`.tres` lisible et éditable à la main dans l'Inspector.

Nouveau plugin : `addons/ludo_path_system/` avec `LudoPathSegment`,
`LudoPathDescriptor` (le cache), `LudoPlayerPath` (compose l'anneau partagé
+ le couloir final propre à chaque joueur) et `LudoBoardLayout` (le bundle
exporté que le jeu charge).

**Découverte amusante.** En creusant le projet, un prototype non commité
(`addons/new folder/`) faisait déjà quasiment exactement ce design — signe
qu'une session précédente avait déjà exploré cette direction sans la
finaliser. Le contenu a été repris et intégré au lieu d'être réinventé.

## Chapitre 2 — Ménage dans les systèmes concurrents

**Le problème.** Trois systèmes de géométrie de plateau coexistaient :
des tableaux codés en dur (`board_generator.gd`), un addon "peindre puis
détecter" (`ludo_board_generator`, jamais réellement branché au jeu), et le
nouveau système par segments. Trois sources de vérité pour la même chose.

**La décision.** Le nouveau système par segments remplace les deux autres
entièrement. Une petite règle de conception a émergé de cette étape :
`LudoPathSegment` supporte un cas où deux segments partagent une case
(jonction dupliquée si `offset == Vector2i.ZERO`), utile pour des formes de
plateau non standard, mais **le plateau classique ne doit jamais l'utiliser**
(sinon `RING_SIZE` ne vaut plus 52) — d'où une validation explicite qui
compare la longueur réelle de l'anneau à la constante attendue.

## Chapitre 3 — Le bug qui a failli effacer des réglages

**Le problème.** En testant le nouveau système en ligne de commande
(scripts headless), une resource (`BoardTuning.tres`, les réglages
visuels du plateau) s'est retrouvée totalement vidée de ses valeurs après
une simple ouverture de l'éditeur.

**La cause.** Dans Godot 4, une `Resource` dont le script n'est **pas**
marqué `@tool` devient une instance "placeholder" dès que l'éditeur la
charge — ses propriétés `@export` deviennent invisibles, et si l'éditeur
la ré-enregistre à ce moment-là, elles sont perdues pour de bon. C'est
exactement ce qui s'est passé.

**La leçon, généralisée à tout le projet.** Chaque script `Resource` du
projet a été audité et marqué `@tool` (`BoardConfig`, `BoardTuning`, et les
8 fichiers de `ludo_path_system`). Root cause fixée une fois pour toutes,
pas juste patchée localement.

## Chapitre 4 — Un deuxième bug plus sournois : le cache qui ne se rafraîchit pas

**Le problème.** Modifier un segment du plateau dans l'Inspector puis
relancer la génération ("Generate Ludo Board") ne changeait rien à l'affichage.

**La cause.** `LudoPathDescriptor` construit son cache de cellules **une
seule fois**, par design, pour ne pas payer ce coût à chaque frame en jeu.
Mais le peintre de plateau (`LudoBoardPainter`) ne le reconstruisait jamais
avant de peindre — donc il repeignait avec un cache vieux d'une session.

**La correction.** `LudoBoardPainter.paint()` force maintenant un
`rebuild_cache()` explicite avant de lire quoi que ce soit. Un test dédié
(`test_board_painter_repaint.gd`) reproduit exactement ce scénario (cache
déjà construit, segment modifié, on repeint) pour que ça ne revienne jamais.

## Chapitre 5 — Réorienter le plateau sur l'image de référence

**Le problème.** Le plateau généré ne correspondait pas à l'image de
référence du jeu (positions S0/S13/S26/S39 des tuiles de départ par
rapport aux quadrants de couleur).

**La décision.** Plutôt que de recalculer toute la géométrie, une simple
**rotation cyclique** de l'ordre des 4 bras de l'anneau a suffi — la
topologie ne change pas, seul l'indice assigné à chaque bras change. Ça a
permis de garder tous les tests existants valides sans y toucher (la
fermeture de boucle, l'absence de chevauchement, etc. sont invariants par
rotation).

## Chapitre 6 — Identité visuelle par joueur

**Le besoin.** Distinguer visuellement la case de départ et le couloir
final de chaque joueur — jusque-là tout se peignait avec le même mesh
uniforme.

**La décision.** Une nouvelle ressource découplée, `LudoMeshMapping`
(`player_id → id de mesh`), séparée de `LudoBoardLayout` (la géométrie
logique ne doit rien savoir des couleurs — pur souci esthétique). Le
peintre repeint la case de départ de chaque joueur avec un mesh distinct,
en plus de l'anneau uniforme.

## Chapitre 7 — Les yards ne sont pas de la géométrie de chemin

**Le constat du créateur du jeu.** Les positions de yard n'ont pas leur
place dans le système de chemin logique — un yard est un simple état de
pion (`MAISON`) plus un espace de décor, pas une case du parcours.

**La décision.** Retrait complet de `yard_positions` de `LudoBoardLayout`.
À la place : des `Marker3D` placés directement dans la scène
(`board_root.tscn > Yards > Player0..3 > Slot0..3`), déplaçables librement
à la souris dans l'éditeur — sans toucher au code ni à une ressource.
`BoardManager` route l'état `MAISON` vers ces marqueurs au lieu de calculer
une position.

**Bonus.** Le couloir final de chaque joueur, qui dépendait d'un tableau
séparé codé en dur, a été **dérivé mathématiquement** de la direction du
premier pas de son bras d'anneau — une case de moins à maintenir à la main.

## Chapitre 8 — La zone de capture et l'animation case par case (2026-07-12)

**La nouvelle règle.** Un pion capturé ne retourne plus directement dans
son propre yard : il va dans la **zone de capture du joueur qui l'a
capturé** (nouvel état `PawnState.CAPTURED`). Il faut un 6 pour s'en
évader — mais cette évasion le renvoie dans son propre yard, pas
directement sur l'anneau ; la sortie de yard classique s'applique ensuite
normalement, sans aucun changement de règle à cet endroit.

**L'animation.** Le déplacement d'un pion se faisait auparavant en un seul
mouvement fluide départ→arrivée. Il fallait qu'il visite chaque case
intermédiaire, et qu'une capture déclenche une animation à part (le pion
capturé part vers la zone de capture *après* que le capteur ait fini de
bouger). Techniquement, tout ça tient sur un seul `Tween` avec des étapes
séquentielles — Godot les joue dans l'ordre tout seul, pas besoin de
synchronisation manuelle entre les deux animations.

**Un piège relevé en cours de route.** Pour animer case par case, il faut
connaître la position de *départ* du pion — mais `RuleEngine.apply_move()`
mute l'état du pion *avant* que l'animation ne soit déclenchée. Solution :
`TurnManager` prend un instantané (`old_state`, `old_progress`) juste avant
d'appliquer le coup, pour le transmettre à l'animation.

---

## Où en est le projet

**Fait et testé** : système de chemin par segments, plateau classique
dérivé et validé automatiquement, identité visuelle par joueur, yards et
zones de capture en `Marker3D` éditables à la souris, règles complètes
(barrières, captures, home lane, victoire), animation case par case.

**En attente** : les pions utilisent encore des `Marker3D` invisibles en
guise de mesh (les vrais modèles 3D restent à brancher), la sélection à la
souris n'est encore qu'un stub (elle prend automatiquement le premier pion
jouable), et un fichier de réglages (`BoardTuning.tres`) attend d'être
restauré après une fausse manip.
