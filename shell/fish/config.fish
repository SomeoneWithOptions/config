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

