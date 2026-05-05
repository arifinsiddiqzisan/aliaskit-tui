#!/usr/bin/env bash

# core/complex.sh - Shared helpers for complex custom commands

ak_complex_list_placeholders() {
    local template="$1"
    printf "%s" "$template" | grep -oE '\[[^][]+\]|\{[^{}]+\}' || true
}

ak_complex_placeholder_kind() {
    local token="$1"
    case "$token" in
        \[*\]) echo "post" ;;
        \{*\}) echo "pre" ;;
        *) echo "unknown" ;;
    esac
}

ak_complex_placeholder_inner() {
    local token="$1"
    token="${token#[}"
    token="${token%]}"
    token="${token#\{}"
    token="${token%\}}"
    printf "%s" "$token"
}

ak_complex_placeholder_name() {
    local inner
    inner=$(ak_complex_placeholder_inner "$1")
    printf "%s" "$inner" | cut -d'.' -f1
}

ak_complex_placeholder_extension() {
    local inner tail
    inner=$(ak_complex_placeholder_inner "$1")
    if [[ "$inner" == *.* ]]; then
        tail="${inner#*.}"
        printf "%s" "$tail"
    else
        printf ""
    fi
}

ak_complex_escape_sed_replacement() {
    printf '%s' "$1" | sed -e 's/[\\&]/\\&/g'
}

ak_complex_replace_literal() {
    local haystack="$1"
    local needle="$2"
    local replacement="$3"
    python3 - "$haystack" "$needle" "$replacement" <<'PY'
import sys
haystack, needle, replacement = sys.argv[1:4]
sys.stdout.write(haystack.replace(needle, replacement))
PY
}

ak_complex_shell_escape_fragment() {
    local fragment="$1"
    python3 - "$fragment" <<'PY'
import shlex
import sys

fragment = sys.argv[1]
sys.stdout.write(' '.join(shlex.quote(part) for part in shlex.split(fragment)))
PY
}

ak_complex_param_keys_from_template() {
    local template="$1"
    local kind="$2"
    local token token_kind inner
    while IFS= read -r token; do
        [[ -n "$token" ]] || continue
        token_kind=$(ak_complex_placeholder_kind "$token")
        [[ "$token_kind" == "$kind" ]] || continue
        inner=$(ak_complex_placeholder_inner "$token")
        printf "%s\n" "$inner"
    done < <(ak_complex_list_placeholders "$template")
}

ak_complex_param_names_from_template() {
    local template="$1"
    local kind="$2"
    local token token_kind name
    while IFS= read -r token; do
        [[ -n "$token" ]] || continue
        token_kind=$(ak_complex_placeholder_kind "$token")
        [[ "$token_kind" == "$kind" ]] || continue
        name=$(ak_complex_placeholder_name "$token")
        printf "%s\n" "$name"
    done < <(ak_complex_list_placeholders "$template")
}

ak_complex_render_pre_json_template() {
    local keys=()
    mapfile -t keys < <(ak_complex_param_names_from_template "$1" pre | awk '!seen[$0]++')
    local first=1 key
    echo "{"
    for key in "${keys[@]}"; do
        [[ -n "$key" ]] || continue
        if (( first == 0 )); then
            echo ","
        fi
        first=0
        printf '  "%s": {\n' "$key"
        printf '    "name-of-constant": "value-of-constant"\n'
        printf '  }'
    done
    echo
    echo "}"
}

ak_complex_edit_pre_params() {
    local existing_json="$1"
    local template="$2"
    local tmpfile expected_keys actual_keys backup_json

    tmpfile=$(mktemp)
    backup_json="$existing_json"

    if [[ -n "$backup_json" ]]; then
        printf "%s\n" "$backup_json" > "$tmpfile"
    else
        ak_complex_render_pre_json_template "$template" > "$tmpfile"
    fi

    "${EDITOR:-nano}" "$tmpfile"

    if ! jq empty "$tmpfile" >/dev/null 2>&1; then
        rm -f "$tmpfile"
        return 1
    fi

    expected_keys=$(ak_complex_param_names_from_template "$template" pre | awk '!seen[$0]++' | sort)
    actual_keys=$(jq -r 'keys[]?' "$tmpfile" | sort)

    if [[ "$expected_keys" != "$actual_keys" ]]; then
        rm -f "$tmpfile"
        return 2
    fi

    cat "$tmpfile"
    rm -f "$tmpfile"
    return 0
}

ak_complex_edit_pre_params_tui() {
    local existing_json="$1"
    local template="$2"
    local param_names=()
    local param_name selected key_count rendered_json
    local tmp_json='{}'
    local option_name option_value action entry_row existing_key

    mapfile -t param_names < <(ak_complex_param_names_from_template "$template" pre | awk '!seen[$0]++')

    if [[ ${#param_names[@]} -eq 0 ]]; then
        printf '{}\n'
        return 0
    fi

    if [[ -n "$existing_json" ]] && jq empty >/dev/null 2>&1 <<<"$existing_json"; then
        tmp_json="$existing_json"
    else
        for param_name in "${param_names[@]}"; do
            tmp_json=$(jq --arg p "$param_name" '. + {($p): {"name-of-constant":"value-of-constant"}}' <<<"$tmp_json")
        done
    fi

    while true; do
        rendered_json=$(jq . <<<"$tmp_json")
        selected=$( {
            printf '%s\n' "JSON Preview:" 
            printf '%s\n' "$rendered_json" | sed 's/^/  /'
            printf '\n'
            for param_name in "${param_names[@]}"; do
                key_count=$(jq -r --arg p "$param_name" '.[$p] | keys | length' <<<"$tmp_json")
                printf '[Edit] %s (%s entries)\n' "$param_name" "$key_count"
            done
            printf '[Save]\n[Cancel]\n'
        } | fzf \
            --height=95% \
            --layout=reverse \
            --border \
            --prompt='Pre Parameters > ' \
            --header=$'Locked JSON structure\n- Top-level pre-parameters cannot be added/removed here\n- Edit values per parameter, then select [Save]' \
            --no-multi) || return 1

        case "$selected" in
            "[Save]")
                printf '%s\n' "$tmp_json"
                return 0
                ;;
            "[Cancel]"|"")
                return 1
                ;;
            "[Edit] "*)
                param_name=$(printf '%s' "$selected" | sed -E 's/^\[Edit\] ([^ ]+) .*/\1/')
                while true; do
                    selected=$( {
                        printf '%s\n' "Parameter: ${param_name}"
                        printf '%s\n' "Current constants:"
                        jq -r --arg p "$param_name" '.[$p] | to_entries[]? | "  - " + .key + " : " + (.value|tostring)' <<<"$tmp_json"
                        printf '\n'
                        printf '[Add Constant]\n[Edit Constant]\n[Delete Constant]\n[Back]\n'
                    } | fzf \
                        --height=95% \
                        --layout=reverse \
                        --border \
                        --prompt="${param_name} > " \
                        --header=$'Manage constants for this locked pre-parameter\nYou can add/edit/delete constant:value pairs here' \
                        --no-multi) || break

                    case "$selected" in
                        "[Add Constant]")
                            option_name=$(printf '\n' | fzf \
                                --height=40% \
                                --layout=reverse \
                                --border \
                                --phony \
                                --prompt='Constant Name > ' \
                                --header="Add constant under ${param_name}" \
                                --bind='enter:accept' \
                                --print-query) || continue
                            option_name=$(printf '%s\n' "$option_name" | awk 'NF{print; exit}')
                            [[ -n "$option_name" ]] || continue

                            option_value=$(printf '\n' | fzf \
                                --height=40% \
                                --layout=reverse \
                                --border \
                                --phony \
                                --prompt='Constant Value > ' \
                                --header="Set value for ${option_name}" \
                                --bind='enter:accept' \
                                --print-query) || continue
                            option_value=$(printf '%s\n' "$option_value" | awk 'NF{print; exit}')
                            [[ -n "$option_value" ]] || continue

                            tmp_json=$(jq --arg p "$param_name" --arg k "$option_name" --arg v "$option_value" '.[$p][$k]=$v' <<<"$tmp_json")
                            ;;
                        "[Edit Constant]")
                            entry_row=$(jq -r --arg p "$param_name" '.[$p] | to_entries[]? | .key + " : " + (.value|tostring)' <<<"$tmp_json" | \
                                fzf --height=60% --layout=reverse --border --prompt='Edit Constant > ' --header="Choose constant to edit") || continue
                            existing_key=$(printf '%s' "$entry_row" | sed 's/ : .*//')
                            [[ -n "$existing_key" ]] || continue

                            option_name=$(printf '%s\n' "$existing_key" | fzf \
                                --height=40% \
                                --layout=reverse \
                                --border \
                                --phony \
                                --prompt='Constant Name > ' \
                                --header="Rename constant (or keep same)" \
                                --bind='enter:accept' \
                                --print-query \
                                --query="$existing_key") || continue
                            option_name=$(printf '%s\n' "$option_name" | awk 'NF{print; exit}')
                            [[ -n "$option_name" ]] || continue

                            option_value=$(printf '%s\n' "$(jq -r --arg p "$param_name" --arg k "$existing_key" '.[$p][$k]' <<<"$tmp_json")" | fzf \
                                --height=40% \
                                --layout=reverse \
                                --border \
                                --phony \
                                --prompt='Constant Value > ' \
                                --header="Edit value for ${option_name}" \
                                --bind='enter:accept' \
                                --print-query \
                                --query="$(jq -r --arg p "$param_name" --arg k "$existing_key" '.[$p][$k]' <<<"$tmp_json")") || continue
                            option_value=$(printf '%s\n' "$option_value" | awk 'NF{print; exit}')
                            [[ -n "$option_value" ]] || continue

                            tmp_json=$(jq --arg p "$param_name" --arg old "$existing_key" 'del(.[$p][$old])' <<<"$tmp_json")
                            tmp_json=$(jq --arg p "$param_name" --arg k "$option_name" --arg v "$option_value" '.[$p][$k]=$v' <<<"$tmp_json")
                            ;;
                        "[Delete Constant]")
                            entry_row=$(jq -r --arg p "$param_name" '.[$p] | to_entries[]? | .key + " : " + (.value|tostring)' <<<"$tmp_json" | \
                                fzf --height=60% --layout=reverse --border --prompt='Delete Constant > ' --header="Choose constant to delete") || continue
                            existing_key=$(printf '%s' "$entry_row" | sed 's/ : .*//')
                            [[ -n "$existing_key" ]] || continue
                            tmp_json=$(jq --arg p "$param_name" --arg k "$existing_key" 'del(.[$p][$k])' <<<"$tmp_json")
                            ;;
                        "[Back]"|"")
                            break
                            ;;
                    esac
                done
                ;;
        esac
    done
}

__ak_complex_exec() {
    local parameters_file="$1"
    shift

    if ! command -v jq >/dev/null 2>&1; then
        echo "jq is required for complex commands." >&2
        return 1
    fi

    [[ -f "$parameters_file" ]] || {
        echo "Missing parameters file: $parameters_file" >&2
        return 1
    }

    local genuine_command custom_command pre_json
    genuine_command=$(jq -r '.genuine_command // empty' "$parameters_file")
    custom_command=$(jq -r '.custom_command // empty' "$parameters_file")
    pre_json=$(jq -c '.pre_parameters // {}' "$parameters_file")

    [[ -n "$genuine_command" && -n "$custom_command" ]] || {
        echo "Invalid complex command definition." >&2
        return 1
    }

    local tokens=()
    mapfile -t tokens < <(ak_complex_list_placeholders "$custom_command")

    declare -A provided=()
    declare -A token_by_name=()
    local token name value arg positional_mode=1
    for token in "${tokens[@]}"; do
        name=$(ak_complex_placeholder_name "$token")
        token_by_name["$name"]="$token"
    done

    for arg in "$@"; do
        if [[ "$arg" == *=* ]]; then
            positional_mode=0
            name="${arg%%=*}"
            value="${arg#*=}"
            value="${value%\"}"
            value="${value#\"}"
            value="${value%\'}"
            value="${value#\'}"
            provided["$name"]="$value"
        fi
    done

    if (( positional_mode == 1 )); then
        local i=0
        for token in "${tokens[@]}"; do
            name=$(ak_complex_placeholder_name "$token")
            provided["$name"]="${1:-}"
            [[ $# -gt 0 ]] && shift
            ((i++))
        done
    fi

    local final_command="$genuine_command"
    local replacement quoted mapped inner ext base output_value replacement_kind
    local type_value="${provided[type]:-}"

    while IFS= read -r token; do
        [[ -n "$token" ]] || continue
        name=$(ak_complex_placeholder_name "$token")
        inner=$(ak_complex_placeholder_inner "$token")
        replacement="${provided[$name]:-}"
        replacement_kind="post"

        if [[ $(ak_complex_placeholder_kind "$token") == "pre" ]]; then
            mapped=$(jq -r --arg param "$name" --arg key "$replacement" '.pre_parameters[$param][$key] // empty' "$parameters_file")
            if [[ -n "$mapped" ]]; then
                replacement="$mapped"
                replacement_kind="pre_mapped"
            fi
        else
            ext=$(ak_complex_placeholder_extension "$token")
            base="$name"

            if [[ "$base" == "input" && -n "$ext" && "$ext" != "anyextention" && "$ext" != "anyextension" ]]; then
                if [[ "$replacement" != *."$ext" ]]; then
                    echo "Invalid input for $token. Expected .$ext file." >&2
                    return 1
                fi
            fi

            if [[ "$base" == "output" ]]; then
                if [[ -n "$type_value" ]]; then
                    output_value="$replacement"
                    output_value="${output_value%.*}"
                    replacement="${output_value}.${type_value}"
                elif [[ -n "$ext" ]]; then
                    if [[ "$replacement" != *.* ]]; then
                        replacement="${replacement}.${ext}"
                    fi
                fi
            fi
        fi

        if [[ "$replacement_kind" == "pre_mapped" ]]; then
            quoted=$(ak_complex_shell_escape_fragment "$replacement")
        else
            printf -v quoted '%q' "$replacement"
        fi
        final_command=$(ak_complex_replace_literal "$final_command" "$token" "$quoted")
    done < <(ak_complex_list_placeholders "$genuine_command")

    eval "$final_command"
}