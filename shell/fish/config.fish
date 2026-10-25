alias oq='omarchy-qemu'
alias t='terraform'
set -g fish_greeting ""

fzf_key_bindings

if command -q mise
    mise activate fish | source
end

# playwright-cli defaults to Google Chrome; Omarchy ships Chromium instead.
if test -x /usr/bin/chromium
    set -gx PLAYWRIGHT_MCP_EXECUTABLE_PATH /usr/bin/chromium
end

# xAI Grok on Vertex via service-account JSON, no gcloud login needed.
set -gx GOOGLE_APPLICATION_CREDENTIALS /home/andres/it-tools-4fc1b6dd-9f8e204c0503.json
set -gx XAI_VERTEX_PROJECT_ID it-tools-4fc1b6dd
