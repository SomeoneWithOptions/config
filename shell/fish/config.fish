alias oq='omarchy-qemu'
alias t='terraform'
set -g fish_greeting ""

if command -q mise
    mise activate fish | source
end

# xAI Grok on Vertex via service-account JSON, no gcloud login needed.
set -gx GOOGLE_APPLICATION_CREDENTIALS /home/andres/it-tools-4fc1b6dd-9f8e204c0503.json
set -gx XAI_VERTEX_PROJECT_ID it-tools-4fc1b6dd
