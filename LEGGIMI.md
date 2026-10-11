# Moto Cross Roblox

Gioco Roblox con moto da cross. Si ricomincia da zero.

- Passo 1 (fatto): la moto 3D (Yamaha YZ125 blu) montata sui perni.
- Passo 2 (versione 2 degli script): ogni giocatore ha la sua moto, **E** per salire/scendere, guida base **W** gas, **S** freno, **A/D** sterzo, con piega in curva, sospensioni e campo visivo che si allarga con la velocità.
- Passo 3 (versione 3): corpo slanciato (altezza x1,3, larghezza x0,8) e posa vera del pilota: mani sulle manopole, piedi sulle pedane, ginocchia piegate, busto in avanti; il corpo va indietro accelerando, avanti frenando, dentro le curve e molleggia.
- Versione 7: piega fino a 60°, camera che segue la moto in curva (libera col mouse, torna dietro dopo 1,5 s) e si inclina, sgommata con S in velocità (fumo + righe nere) e burnout con W+S da fermo (A/D per girare sul posto).
- Prossimi: impennata con SHIFT, caduta con ragdoll, moto 2026 rifatta dalle foto.

## File

| File | Cosa è | Dove va in Roblox Studio |
|---|---|---|
| `MotoYZ125.glb` | modello 3D della moto | File → Import 3D, poi in **ServerStorage**, rinominato **MotoModello** |
| `roblox/MotoServer.lua` | Script | **ServerScriptService** → Script chiamato `MotoServer` |
| `roblox/MotoClient.lua` | LocalScript | **StarterPlayer → StarterPlayerScripts** → LocalScript chiamato `MotoClient` |
| `roblox/PosaPilota.lua` | ModuleScript | **ReplicatedStorage** → ModuleScript chiamato `PosaPilota` |
| `test/` | prova della posa fuori da Roblox (`./test/esegui.sh`, serve `luau`) | – |
| `strumenti/genera_moto.py` | programma che crea `MotoYZ125.glb` (non va in Roblox) | – |
| `anteprime/` | immagini di controllo del modello | – |

## Mettere gli script in Studio senza copia-incolla

Nella cartella `studio/` ci sono `MotoServer.rbxmx`, `MotoClient.rbxmx`, `PosaPilota.rbxmx`: clic destro sulla cartella giusta in Studio → **Insert from File...** e scegli il file. (Se incolli a mano, controlla che l'ultima riga sia stata copiata.)

## Il modello 3D

- Misure prese dalla foto: passo 1443 mm, 1 stud = 0,28 m, ruota dietro 19", davanti 21".
- Origine = asse della ruota dietro, davanti = −Z, su = +Y, destra = +X. Terreno a Y = −1,19.
- Ogni pezzo si chiama `Gruppo_Colore`. Gruppi: `Corpo`, `Sterzo`, `Forcella`, `RuotaDavanti`, `Forcellone`, `RuotaDietro`.
- Tre cubetti `RIF_Origine`, `RIF_Avanti` (5 stud avanti), `RIF_Su` (3 stud su) servono allo script per rimettere scala e rotazione giuste dopo l'importazione.

Per rigenerare il modello: `pip install trimesh shapely mapbox-earcut numpy` e poi `python3 strumenti/genera_moto.py`.

## Giunti (per i prossimi passi)

`Corpo` (ancorato) → `Giunto_Sterzo` (gira sull'asse di sterzo a 24°) → `Giunto_Forcella` (scorre lungo la forcella) → `Giunto_RuotaDavanti` (gira).
`Corpo` → `Giunto_Forcellone` (ruota sul perno) → `Giunto_RuotaDietro` (gira).
Sono `Motor6D`: il client li muove con `.Transform`.
