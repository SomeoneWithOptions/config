alias t='terraform'
set -g fish_greeting ""

if command -q mise
    mise activate fish | source
end

# Reuse Pi's configured OpenRouter key without duplicating the secret.
if test -f ~/.pi/agent/auth.json
    set -l _openrouter_key (python -c 'import json, pathlib; p = pathlib.Path.home() / ".pi/agent/auth.json"; print(json.load(open(p)).get("openrouter", {}).get("key", ""))' 2>/dev/null)
    if test -n "$_openrouter_key"
        set -gx OPENROUTER_API_KEY $_openrouter_key
    end
    set -e _openrouter_key
end
