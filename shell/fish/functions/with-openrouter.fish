function with-openrouter --description 'Run command with OpenRouter key from 1Password'
    if test (count $argv) -eq 0
        echo 'Usage: with-openrouter <command> [args...]' >&2
        return 2
    end

    env OPENROUTER_API_KEY='op://Private/OpenRouter/personal' op run -- $argv
end
