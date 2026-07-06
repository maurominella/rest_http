#!/usr/bin/env bash
# Rigenera TUTTI i bearer token usati dai file .http in un colpo solo e li scrive
# dentro .vscode/settings.json (ambiente "dev"), cosi' i {{bearertoken_for_...}}
# nelle richieste REST Client sono sempre validi. Lancialo a mano ~1 volta l'ora.
#
# La mappatura variabile -> risorsa (--resource) e' definita in token-mapping.json:
#   { "bearertoken_for_aiazurecom": "https://ai.azure.com/", ... }
# Aggiungi/rimuovi righe li' senza toccare questo script.
#
# Uso:  ./refresh-tokens.sh
set -euo pipefail
cd "$(dirname "$0")"

MAPPING="token-mapping.json"
SETTINGS=".vscode/settings.json"
ENV_NAME="dev"

command -v az >/dev/null 2>&1 || { echo "ERRORE: 'az' non trovato nel PATH." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERRORE: 'python3' non trovato nel PATH." >&2; exit 1; }
[[ -f "$MAPPING"  ]] || { echo "ERRORE: manca $MAPPING" >&2; exit 1; }
[[ -f "$SETTINGS" ]] || { echo "ERRORE: manca $SETTINGS" >&2; exit 1; }

echo "Rigenero i token (env '$ENV_NAME') da $MAPPING ..."

python3 - "$MAPPING" "$SETTINGS" "$ENV_NAME" <<'PY'
import json, subprocess, sys

mapping_path, settings_path, env_name = sys.argv[1], sys.argv[2], sys.argv[3]

with open(mapping_path, encoding="utf-8") as f:
    mapping = json.load(f)
with open(settings_path, encoding="utf-8") as f:
    settings = json.load(f)

env = settings.setdefault("rest-client.environmentVariables", {}).setdefault(env_name, {})

ok, failed = [], []
for var, resource in mapping.items():
    try:
        token = subprocess.run(
            ["az", "account", "get-access-token",
             "--resource", resource, "--query", "accessToken", "-o", "tsv"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        if not token:
            raise RuntimeError("token vuoto")
        env[var] = token
        ok.append(var)
        print(f"  OK    {var}  <-  {resource}")
    except (subprocess.CalledProcessError, RuntimeError) as e:
        detail = getattr(e, "stderr", "") or str(e)
        failed.append((var, detail.strip()))
        print(f"  FAIL  {var}  <-  {resource}", file=sys.stderr)

with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(settings, f, indent=4, ensure_ascii=False)
    f.write("\n")

print(f"\nAggiornati {len(ok)} token in {settings_path}.")
if failed:
    print(f"{len(failed)} falliti:", file=sys.stderr)
    for var, detail in failed:
        last = detail.splitlines()[-1] if detail else "errore sconosciuto"
        print(f"  - {var}: {last}", file=sys.stderr)
    sys.exit(1)
PY

echo "Fatto."
