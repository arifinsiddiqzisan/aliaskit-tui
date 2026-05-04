#!/usr/bin/env bash

# core/sync_registry.sh - Shared helpers for package pull/sync workflow

ak_sync_require_tool() {
    local tool="$1"
    command -v "$tool" >/dev/null 2>&1 || {
        echo "$tool is required for this operation." >&2
        return 1
    }
}

ak_sync_init_state_files() {
    ak_registry_bootstrap
    ak_sync_require_tool jq || return 1
    [[ -s "$AK_SYNC_STATE_FILE" ]] || printf '{"packages":[]}\n' > "$AK_SYNC_STATE_FILE"
    [[ -s "$AK_SYNC_MAP_FILE" ]] || printf '{"packages":{}}\n' > "$AK_SYNC_MAP_FILE"
}

ak_sync_now_iso() {
    date -Iseconds
}

ak_sync_slugify_repo_name() {
    printf '%s' "$1" | sed -E 's/\.git$//' | sed 's/[^A-Za-z0-9._-]/_/g'
}

ak_sync_parse_repo_input() {
    local input="$1"
    local normalized owner repo url

    input=$(printf '%s' "$input" | sed 's/[[:space:]]*$//; s/^[[:space:]]*//')
    [[ -n "$input" ]] || return 1

    if printf '%s' "$input" | grep -Eq '^https://github\.com/[^/]+/[^/]+/?$'; then
        normalized=$(printf '%s' "$input" | sed -E 's#^https://github\.com/##; s#/$##; s#\.git$##')
    elif printf '%s' "$input" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; then
        normalized="$input"
    else
        return 1
    fi

    owner="${normalized%%/*}"
    repo="${normalized##*/}"
    repo=$(printf '%s' "$repo" | sed 's/\.git$//')
    url="https://github.com/${owner}/${repo}.git"
    printf '%s\t%s\t%s\n' "$normalized" "$repo" "$url"
}

ak_sync_package_dir() {
    local repo_name="$1"
    printf '%s/%s' "$AK_SYNC_ROOT" "$repo_name"
}

ak_sync_package_custom_dir() {
    local repo_name="$1"
    printf '%s/custom' "$(ak_sync_package_dir "$repo_name")"
}

ak_sync_validate_package_dir() {
    local package_custom_dir="$1"
    [[ -d "$package_custom_dir" ]] || return 1
    [[ -d "$package_custom_dir/modules" ]] || return 1
    find "$package_custom_dir/modules" \( -maxdepth 1 -type f -name '*.sh' -o -path "$package_custom_dir/modules/complex/*" \) | grep -q .
}

ak_sync_upsert_package_state() {
    local package_name="$1" repo_ref="$2" repo_url="$3" branch="$4" package_dir="$5"
    ak_sync_init_state_files || return 1
    local now
    now=$(ak_sync_now_iso)

    jq \
      --arg name "$package_name" \
      --arg repo "$repo_ref" \
      --arg url "$repo_url" \
      --arg branch "$branch" \
      --arg dir "$package_dir" \
      --arg now "$now" \
      '
        .packages = (
          (.packages // [])
          | map(select(.name != $name))
          + [{
              name:$name,
              repo:$repo,
              repo_url:$url,
              branch:$branch,
              package_dir:$dir,
              source_dir:($dir + "/custom"),
              pulled_at:$now,
              last_sync_at:(first((.packages // [])[]? | select(.name == $name) | .last_sync_at) // null)
            }]
        )
      ' "$AK_SYNC_STATE_FILE" > "$AK_SYNC_STATE_FILE.tmp" && mv "$AK_SYNC_STATE_FILE.tmp" "$AK_SYNC_STATE_FILE"
}

ak_sync_list_packages() {
    ak_sync_init_state_files || return 1
    jq -r '.packages[]? | [.name, .repo, (.last_sync_at // "never")] | @tsv' "$AK_SYNC_STATE_FILE"
}

ak_sync_get_package_field() {
    local package_name="$1" field="$2"
    ak_sync_init_state_files || return 1
    jq -r --arg name "$package_name" --arg field "$field" '.packages[]? | select(.name == $name) | .[$field] // empty' "$AK_SYNC_STATE_FILE" | head -n1
}

ak_sync_extract_normal_module_entries() {
    local module_file="$1"
    ak_extract_entries_from_module_file "$module_file"
}

ak_sync_read_normal_module_meta() {
    local module_file="$1"
    local module_name category
    module_name=$(ak_extract_module_name_from_file "$module_file")
    category=$(grep -m 1 '^# CATEGORY:' "$module_file" | sed 's/^# CATEGORY:[[:space:]]*//')
    printf '%s\t%s\n' "$module_name" "$category"
}

ak_sync_find_custom_doc_file() {
    local module_name="$1"
    local doc_file
    for doc_file in "${AK_CUSTOM_DOC_MODULE_DIR}/"*.md; do
        [[ -f "$doc_file" ]] || continue
        if [[ "$(basename "$doc_file" | sed -E 's/^[0-9]+_//; s/\.md$//')" == "$module_name" ]]; then
            printf '%s\n' "$doc_file"
            return 0
        fi
    done
    return 1
}

ak_sync_write_normal_module_from_arrays() {
    local module_file="$1" module_name="$2" category="$3"
    shift 3
    local -n ref_cmds="$1"
    local -n ref_genuines="$2"
    local -n ref_descs="$3"
    local -n ref_usages="$4"
    local -n ref_examples="$5"

    {
        echo "#!/usr/bin/env bash"
        echo "# CATEGORY: ${category}"
        echo "# MODULE: ${module_name}"
        echo ""
        local i
        for i in "${!ref_cmds[@]}"; do
            echo "## ${ref_cmds[$i]}"
            echo "# @desc  ${ref_descs[$i]}"
            echo "# @usage ${ref_usages[$i]}"
            echo "# @example ${ref_examples[$i]}"
            echo "# @genuine ${ref_genuines[$i]}"
            if ! ak_command_is_multiword "${ref_cmds[$i]}"; then
                printf "alias %s='%s'\n" "${ref_cmds[$i]}" "$(printf "%s" "${ref_genuines[$i]}" | sed "s/'/'\\''/g")"
            fi
            echo
        done
    } > "$module_file"
    chmod +x "$module_file"
}

ak_sync_write_normal_doc_from_arrays() {
    local doc_file="$1" module_name="$2"
    shift 2
    local -n ref_cmds="$1"
    local -n ref_genuines="$2"
    local -n ref_descs="$3"
    local -n ref_usages="$4"
    local -n ref_examples="$5"
    local title
    title=$(ak_humanize_module_name "$module_name")

    {
        echo "# ${title}"
        echo
        echo "Custom module managed by package sync."
        echo
        echo "---"
        echo
        echo "## Aliases"
        echo
        local i
        for i in "${!ref_cmds[@]}"; do
            echo "### \`${ref_cmds[$i]}\`"
            echo "- **Description:** ${ref_descs[$i]}"
            echo "- **Usage:** \`${ref_usages[$i]}\`"
            echo "- **Example:** \`${ref_examples[$i]}\`"
            echo
            echo '```bash'
            echo "${ref_cmds[$i]}"
            echo "# Runs: ${ref_genuines[$i]}"
            echo '```'
            echo
        done
        echo "---"
        echo
        echo "{{#template ../templates/footer.md module=${title}}}"
    } > "$doc_file"
}

ak_sync_record_result() {
    local package_name="$1" repo_ref="$2" imported_json="$3" replaced_json="$4" skipped_json="$5"
    ak_sync_init_state_files || return 1
    local now
    now=$(ak_sync_now_iso)

    jq \
      --arg name "$package_name" \
      --arg repo "$repo_ref" \
      --arg now "$now" \
      --argjson imported "$imported_json" \
      --argjson replaced "$replaced_json" \
      --argjson skipped "$skipped_json" \
      '.packages[$name] = {
          repo:$repo,
          last_sync_at:$now,
          imported:$imported,
          replaced:$replaced,
          skipped:$skipped
        }' "$AK_SYNC_MAP_FILE" > "$AK_SYNC_MAP_FILE.tmp" && mv "$AK_SYNC_MAP_FILE.tmp" "$AK_SYNC_MAP_FILE"

    jq \
      --arg name "$package_name" \
      --arg now "$now" \
      '(.packages // []) |= map(if .name == $name then . + {last_sync_at:$now} else . end)' "$AK_SYNC_STATE_FILE" > "$AK_SYNC_STATE_FILE.tmp" && mv "$AK_SYNC_STATE_FILE.tmp" "$AK_SYNC_STATE_FILE"
}