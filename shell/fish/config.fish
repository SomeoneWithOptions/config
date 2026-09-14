alias oq='omarchy-qemu'
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

# xAI Grok on Vertex via service-account JSON, no gcloud login needed.
set -gx GOOGLE_APPLICATION_CREDENTIALS /home/andres/it-tools-4fc1b6dd-9f8e204c0503.json
set -gx XAI_VERTEX_PROJECT_ID it-tools-4fc1b6dd
