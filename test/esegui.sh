#!/bin/sh
# Prova la posa del pilota: ./test/esegui.sh  (serve il programma "luau")
cd "$(dirname "$0")"
LUAU=${LUAU:-luau}
python3 - <<'PY'
s = open("prova_posa.luau").read().replace("--POSA--", open("../roblox/PosaPilota.lua").read())
open("_prova_completa.luau", "w").write(s)
PY
"$LUAU" _prova_completa.luau
