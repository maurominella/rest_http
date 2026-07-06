#!/usr/bin/env bash
# Regenerate ALL bearer tokens used by the .http files in one shot and write them
# into .vscode/settings.json ("dev" environment), so the {{bearertoken_for_...}}
# in REST Client requests are always valid. Run it manually ~once per hour.
#
# The mapping is defined in token-mapping.json: an array of objects with the fields
#   generate_token : "y" to process the entry, any other value = skip
#   token_name     : name of the variable in settings.json (e.g. bearertoken_for_aiazurecom)
#   token_resource : resource/scope of the token
#   token_value    : if set, it is used as-is (no call is made)
#   app_id         : empty -> USER token from the current 'az login' session
#                    set   -> APP token via client-credentials; the secret is read
#                    from settings.json at the key equal to the app_id value.
#                    The 'az login' session is NOT touched: user tokens stay user.
# Rules (with generate_token == "y"):
#   token_value non-empty            -> writes token_value into settings.json
#   token_value empty & app_id empty -> generates a USER token with az
#   token_value empty & app_id set   -> generates an APP token (client-credentials)
# Add/remove entries there without touching this script.
#
# Usage:  ./refresh-tokens.sh
set -euo pipefail
cd "$(dirname "$0")"

MAPPING="token-mapping.json"
SETTINGS=".vscode/settings.json"
ENV_NAME="dev"

command -v az >/dev/null 2>&1 || { echo "ERROR: 'az' not found in PATH." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: 'python3' not found in PATH." >&2; exit 1; }
[[ -f "$MAPPING"  ]] || { echo "ERROR: missing $MAPPING" >&2; exit 1; }
[[ -f "$SETTINGS" ]] || { echo "ERROR: missing $SETTINGS" >&2; exit 1; }

echo "Regenerating tokens (env '$ENV_NAME') from $MAPPING ..."

python3 - "$MAPPING" "$SETTINGS" "$ENV_NAME" <<'PY'
import json, subprocess, sys, urllib.request, urllib.parse, urllib.error

mapping_path, settings_path, env_name = sys.argv[1], sys.argv[2], sys.argv[3]

with open(mapping_path, encoding="utf-8") as f:
    mapping = json.load(f)
with open(settings_path, encoding="utf-8") as f:
    settings = json.load(f)

env = settings.setdefault("rest-client.environmentVariables", {}).setdefault(env_name, {})

_tenant = {}
def current_tenant():
    # Prefer tenant_id from settings.json; fall back to the current az session.
    if "id" not in _tenant:
        tid = str(env.get("tenant_id", "")).strip()
        if not tid:
            tid = subprocess.run(
                ["az", "account", "show", "--query", "tenantId", "-o", "tsv"],
                check=True, capture_output=True, text=True,
            ).stdout.strip()
        _tenant["id"] = tid
    return _tenant["id"]

_signin = {}
def signin_type():
    # 'user' or 'servicePrincipal' depending on how 'az login' was performed.
    if "t" not in _signin:
        _signin["t"] = subprocess.run(
            ["az", "account", "show", "--query", "user.type", "-o", "tsv"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
    return _signin["t"]

def get_user_token(resource):
    token = subprocess.run(
        ["az", "account", "get-access-token", "--tenant", current_tenant(),
         "--resource", resource, "--query", "accessToken", "-o", "tsv"],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    if not token:
        raise RuntimeError("empty token")
    return token

def get_app_token(app_id, secret, resource):
    # OAuth2 v1 client-credentials: 'resource' accepts the same values as --resource.
    url = f"https://login.microsoftonline.com/{current_tenant()}/oauth2/token"
    data = urllib.parse.urlencode({
        "grant_type": "client_credentials",
        "client_id": app_id,
        "client_secret": secret,
        "resource": resource,
    }).encode()
    req = urllib.request.Request(url, data=data, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            payload = json.load(r)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        try:
            err = json.loads(body).get("error_description", body)
        except json.JSONDecodeError:
            err = body
        raise RuntimeError(f"HTTP {e.code}: {err.splitlines()[0]}") from None
    token = payload.get("access_token", "")
    if not token:
        raise RuntimeError("access_token missing from the response")
    return token

ok, skipped, failed = [], [], []
for item in mapping:
    gen = str(item.get("generate_token", "")).strip().lower()
    name = item.get("token_name", "")
    resource = item.get("token_resource", "")
    value = item.get("token_value", "")

    if not name:
        continue

    # Rule 1: generate_token different from "y" -> skip
    if gen != "y":
        skipped.append(name)
        print(f"  SKIP  {name}  (generate_token='{item.get('generate_token', '')}')")
        continue

    # Rule 2: token_value set -> use the literal value
    if value != "":
        env[name] = value
        ok.append(name)
        print(f"  SET   {name}  <-  token_value (provided value)")
        continue

    # Rule 3: token_value empty -> generate the token
    app_id = str(item.get("app_id", "")).strip()
    try:
        if app_id:
            secret = env.get(app_id, "")
            if not secret:
                raise RuntimeError(f"app_secret not found in settings.json at key '{app_id}'")
            env[name] = get_app_token(app_id, secret, resource)
            ok.append(name)
            print(f"  APP   {name}  <-  {resource}  (sp {app_id})")
        else:
            stype = signin_type()
            if stype != "user":
                raise RuntimeError(
                    f"the 'az' session is of type '{stype}', not 'user': "
                    "the token would be an APP token. Run 'az login' as a user "
                    "(or set app_id if you really want an APP token)."
                )
            env[name] = get_user_token(resource)
            ok.append(name)
            print(f"  USER  {name}  <-  {resource}")
    except (subprocess.CalledProcessError, RuntimeError) as e:
        detail = getattr(e, "stderr", "") or str(e)
        failed.append((name, detail.strip()))
        print(f"  FAIL  {name}  <-  {resource}", file=sys.stderr)

with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(settings, f, indent=4, ensure_ascii=False)
    f.write("\n")

print(f"\nUpdated {len(ok)} token(s) in {settings_path} (skipped: {len(skipped)}).")
if failed:
    print(f"{len(failed)} failed:", file=sys.stderr)
    for var, detail in failed:
        last = detail.splitlines()[-1] if detail else "unknown error"
        print(f"  - {var}: {last}", file=sys.stderr)
    sys.exit(1)
PY

echo "Done."
