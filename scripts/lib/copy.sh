# CHECK-aware filesystem helpers used by the config replay.
# Sourcing script must define CHECK (0/1) and DRIFT (integer) and source
# lib/report.sh first. link_agent_skill also calls report_warning.

# report_drift TARGET [SOURCE] [NOTE]
# Prints one "== TARGET: ..." header per drifted target so callers can count them.
# With SOURCE, shows what applying the repo would change (- live, + repo).
report_drift() {
    local target="$1" source="${2:-}" note="${3:-}"

    DRIFT=$((DRIFT + 1))
    if [[ -n "$note" ]]; then
        printf '\n== %s: %s\n' "$target" "$note"
    elif [[ ! -e "$target" ]]; then
        printf '\n== %s: missing (repo would create it)\n' "$target"
    elif [[ -d "$source" ]]; then
        printf '\n== %s: differs (- live, + repo)\n' "$target"
        diff -ru "$target" "$source" || true
    else
        printf '\n== %s: differs (- live, + repo)\n' "$target"
        diff -u -L live -L repo "$target" "$source" || true
    fi
}

copy_required() {
    local source_path="$1"
    local dest_path="$2"

    if [[ ! -f "$source_path" ]]; then
        printf 'Missing required config file: %s\n' "$source_path" >&2
        exit 1
    fi

    if [[ -f "$dest_path" ]] && cmp -s "$source_path" "$dest_path"; then
        return
    fi
    if (( CHECK )); then
        report_drift "$dest_path" "$source_path"
        return
    fi

    mkdir -p "$(dirname "$dest_path")"
    cp "$source_path" "$dest_path"
    printf 'Updated %s\n' "$dest_path"
}

copy_required_if_missing() {
    local source_path="$1"
    local dest_path="$2"

    if [[ ! -f "$source_path" ]]; then
        printf 'Missing required config file: %s\n' "$source_path" >&2
        exit 1
    fi

    if [[ -e "$dest_path" ]]; then
        return
    fi
    if (( CHECK )); then
        report_drift "$dest_path" "" "missing (seed file; repo would create it)"
        return
    fi

    mkdir -p "$(dirname "$dest_path")"
    cp "$source_path" "$dest_path"
    printf 'Created %s\n' "$dest_path"
}

copy_executable_required() {
    local source_path="$1"
    local dest_path="$2"

    copy_required "$source_path" "$dest_path"
    (( CHECK )) || chmod +x "$dest_path"
}

copy_dir_required() {
    local source_path="$1"
    local dest_path="$2"

    if [[ ! -d "$source_path" ]]; then
        printf 'Missing required config directory: %s\n' "$source_path" >&2
        exit 1
    fi

    # Content only: rsync's itemize also flags mtime, which differs between
    # checkouts of identical files.
    if (( CHECK )); then
        if [[ ! -d "$dest_path" ]] || ! diff -qr "$source_path" "$dest_path" >/dev/null 2>&1; then
            report_drift "$dest_path" "$source_path"
        fi
        return
    fi

    if command -v rsync >/dev/null 2>&1; then
        local changes
        mkdir -p "$(dirname "$dest_path")"
        changes=$(rsync -a --delete --itemize-changes "$source_path/" "$dest_path/")
        if [[ -n "$changes" ]]; then
            printf 'Updated %s\n' "$dest_path"
        fi
        return
    fi

    if [[ -d "$dest_path" ]] && diff -qr "$source_path" "$dest_path" >/dev/null 2>&1; then
        return
    fi
    mkdir -p "$(dirname "$dest_path")"
    rm -rf "$dest_path"
    cp -R "$source_path" "$dest_path"
    printf 'Updated %s\n' "$dest_path"
}

append_line_once() {
    local line="$1"
    local file="$2"

    if [[ -f "$file" ]] && grep -qxF "$line" "$file"; then
        return
    fi
    if (( CHECK )); then
        report_drift "$file" "" "missing line: $line"
        return
    fi
    mkdir -p "$(dirname "$file")"
    touch "$file"
    printf '%s\n' "$line" >> "$file"
}

# Shared skills (pi + Claude Code) install into ~/.agents/skills; each agent's
# skill dir gets a relative symlink so one copy serves both.
link_agent_skill() {
    local name="$1" link_dir="$2" rel_target="$3"
    local link="$link_dir/$name"

    if [[ -L "$link" && "$(readlink "$link")" == "$rel_target/$name" ]]; then
        return
    fi
    if [[ -e "$link" ]]; then
        # Never clobber a real dir or a deliberate user-made link.
        if (( CHECK )); then
            report_drift "$link" "" "exists but is not the expected symlink to $rel_target/$name"
        else
            report_warning "$link exists but is not the expected symlink to $rel_target/$name; left untouched."
        fi
        return
    fi
    if (( CHECK )); then
        report_drift "$link" "" "missing (repo would symlink it to $rel_target/$name)"
        return
    fi
    mkdir -p "$link_dir"
    ln -s "$rel_target/$name" "$link"
    printf 'Linked %s -> %s\n' "$link" "$rel_target/$name"
}

