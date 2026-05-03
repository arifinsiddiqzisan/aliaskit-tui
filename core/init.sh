#!/usr/bin/env bash

# core/init.sh - Initializes aliaskit, loads configs, and sources enabled modules

AK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AK_ROOT
export AK_CONFIG="${HOME}/.aliaskit.conf"

# Detect OS and export for conditional use in modules
_os_type="$(uname -s)"
case "$_os_type" in
    Linux*)
        if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
            export AK_OS="wsl"
        else
            export AK_OS="linux"
        fi
        ;;
    Darwin*)              export AK_OS="macos" ;;
    MINGW*|CYGWIN*|MSYS*) export AK_OS="windows" ;;
    *)                    export AK_OS="unknown" ;;
esac
unset _os_type

# Copy default config if it doesn't exist
if [[ ! -f "$AK_CONFIG" ]]; then
    # In case installation hasn't fully copied it yet, try local layout
    if [[ -f "${AK_ROOT}/config/aliaskit.conf.default" ]]; then
        cp "${AK_ROOT}/config/aliaskit.conf.default" "$AK_CONFIG"
    fi
fi

# Load configs
if [[ -f "$AK_CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "$AK_CONFIG"
fi

# Registry / custom module helpers
if [[ -f "${AK_ROOT}/core/registry.sh" ]]; then
    # shellcheck source=/dev/null
    source "${AK_ROOT}/core/registry.sh"
    ak_registry_bootstrap
fi

if [[ -f "${AK_ROOT}/core/complex.sh" ]]; then
    # shellcheck source=/dev/null
    source "${AK_ROOT}/core/complex.sh"
fi

declare -gA AK_NORMAL_CUSTOM_GENUINES=()
declare -ga AK_NORMAL_CUSTOM_FIRST_WORDS=()

ak_append_runtime_args_to_command() {
    local base_command="$1"
    shift
    local final_command="$base_command"
    local arg quoted
    for arg in "$@"; do
        printf -v quoted ' %q' "$arg"
        final_command+="$quoted"
    done
    printf '%s' "$final_command"
}

ak_register_normal_custom_command() {
    local command_name="$1"
    local genuine_command="$2"
    local first_word

    command_name=$(ak_normalize_command_name "$command_name")
    [[ -n "$command_name" && -n "$genuine_command" ]] || return 0

    if ak_command_exists_official "$command_name"; then
        return 0
    fi

    AK_NORMAL_CUSTOM_GENUINES["$command_name"]="$genuine_command"
    first_word=$(ak_command_first_word "$command_name")
    if ! printf '%s\n' "${AK_NORMAL_CUSTOM_FIRST_WORDS[@]}" | grep -qx "$first_word"; then
        AK_NORMAL_CUSTOM_FIRST_WORDS+=("$first_word")
    fi
}

ak_load_normal_custom_commands() {
    local module_file cmd desc usage example genuine
    for module_file in "${AK_CUSTOM_MODULE_DIR}/"*.sh; do
        [[ -f "$module_file" ]] || continue
        while IFS=$'\t' read -r cmd desc usage example genuine; do
            [[ -n "$cmd" ]] || continue
            ak_register_normal_custom_command "$cmd" "$genuine"
        done < <(ak_extract_entries_from_module_file "$module_file")
    done
}

__ak_dispatch_normal_custom_command() {
    local first_word="$1"
    shift

    local phrase candidate candidate_tail candidate_count best_phrase="" best_count=0
    local -a candidate_parts remaining_args=()

    for phrase in "${!AK_NORMAL_CUSTOM_GENUINES[@]}"; do
        [[ "$(ak_command_first_word "$phrase")" == "$first_word" ]] || continue

        candidate="$phrase"
        candidate_tail="${candidate#${first_word}}"
        candidate_tail="${candidate_tail# }"

        if [[ -z "$candidate_tail" ]]; then
            candidate_count=1
            if (( candidate_count > best_count )); then
                best_phrase="$candidate"
                best_count=$candidate_count
            fi
            continue
        fi

        read -r -a candidate_parts <<< "$candidate_tail"
        if (( $# < ${#candidate_parts[@]} )); then
            continue
        fi

        local i matched=1
        for i in "${!candidate_parts[@]}"; do
            if [[ "${candidate_parts[$i]}" != "${@:$((i+1)):1}" ]]; then
                matched=0
                break
            fi
        done

        if (( matched == 1 )); then
            candidate_count=$((1 + ${#candidate_parts[@]}))
            if (( candidate_count > best_count )); then
                best_phrase="$candidate"
                best_count=$candidate_count
            fi
        fi
    done

    if [[ -n "$best_phrase" ]]; then
        if (( $# >= best_count - 1 )); then
            remaining_args=("${@:$best_count}")
        fi
        eval "$(ak_append_runtime_args_to_command "${AK_NORMAL_CUSTOM_GENUINES[$best_phrase]}" "${remaining_args[@]}")"
        return $?
    fi

    command "$first_word" "$@"
}

ak_enable_normal_custom_dispatchers() {
    local first_word
    for first_word in "${AK_NORMAL_CUSTOM_FIRST_WORDS[@]}"; do
        unalias "$first_word" >/dev/null 2>&1 || true
        eval "${first_word}() { __ak_dispatch_normal_custom_command ${first_word} \"\$@\"; }"
    done
}

# Source enabled modules
for module_file in "${AK_ROOT}/modules/"*.sh; do
    if [[ -f "$module_file" ]]; then
        module_name=$(basename "$module_file" | sed -E 's/^[0-9]+_//' | sed 's/\.sh$//')
        var_name="AK_ENABLE_$(echo "$module_name" | tr '[:lower:]' '[:upper:]')"
        
        # Check if module is enabled (defaults to true if not explicitly set to false)
        if [[ "${!var_name}" != "false" ]]; then
            # shellcheck source=/dev/null
            source "$module_file"
        fi
    fi
done

# Source custom modules (keeps official priority on conflicts)
if declare -f ak_source_custom_modules_with_conflict_guard >/dev/null 2>&1; then
    ak_source_custom_modules_with_conflict_guard
fi

ak_load_normal_custom_commands
ak_enable_normal_custom_dispatchers

if declare -f ak_collect_complex_command_paths >/dev/null 2>&1; then
    while IFS= read -r complex_command_file; do
        [[ -f "$complex_command_file" ]] || continue
        complex_command_name=$(awk '/^## /{ print substr($0,4); exit }' "$complex_command_file")
        if [[ -n "$complex_command_name" ]] && ak_command_exists_official "$complex_command_name"; then
            continue
        fi
        # shellcheck source=/dev/null
        source "$complex_command_file"
    done < <(ak_collect_complex_command_paths)
    ak_write_custom_index
fi

# The root `ak` command router
ak() {
    local cmd="${1:-help}"
    shift

    case "$cmd" in
        help|search|list|modules|config|update|reload|stats|version|--version|-v|add|addc|edit|custom)
            if [[ "$cmd" == "version" || "$cmd" == "--version" || "$cmd" == "-v" ]]; then
                bash "${AK_ROOT}/core/help.sh" "version"
            elif [[ -f "${AK_ROOT}/core/${cmd}.sh" ]]; then
                bash "${AK_ROOT}/core/${cmd}.sh" "$@"
            elif [[ -f "${AK_ROOT}/core/help.sh" ]]; then
                bash "${AK_ROOT}/core/help.sh" "$cmd" "$@"
            fi
            ;;
        *)
            echo "Unknown command: $cmd"
            bash "${AK_ROOT}/core/help.sh"
            ;;
    esac
}
