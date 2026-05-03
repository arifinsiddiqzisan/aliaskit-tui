#!/usr/bin/env bash

# core/edit.sh - Edit/delete custom and complex modules/commands

AK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${AK_ROOT}/core/registry.sh"
# shellcheck source=/dev/null
source "${AK_ROOT}/core/complex.sh"

print_color() {
    local color="$1"
    local text="$2"
    case "$color" in
        green) echo -e "\033[32m${text}\033[0m" ;;
        yellow) echo -e "\033[33m${text}\033[0m" ;;
        red) echo -e "\033[31m${text}\033[0m" ;;
        cyan) echo -e "\033[36m${text}\033[0m" ;;
        bold) echo -e "\033[1m${text}\033[0m" ;;
        *) echo "$text" ;;
    esac
}

escape_single_quotes() {
    local s="$1"
    printf "%s" "$s" | sed "s/'/'\\''/g"
}

normalize_command_input() {
    ak_normalize_command_name "$1"
}

prompt_with_default() {
    local label="$1"
    local def="$2"
    local value out

    if command -v fzf >/dev/null 2>&1; then
        out=$(printf '\n' | fzf \
            --height=95% \
            --layout=reverse \
            --border \
            --phony \
            --prompt="${label} > " \
            --header="ak edit • Enter value (ESC to cancel)" \
            --bind='enter:accept' \
            --print-query \
            --query="$def") || return 1
        value=$(printf "%s\n" "$out" | head -n1)
        if [[ -z "$value" ]]; then
            echo "$def"
        else
            echo "$value"
        fi
        return 0
    fi

    read -r -p "$label [$def]: " value
    if [[ -z "$value" ]]; then
        echo "$def"
    else
        echo "$value"
    fi
}

pick_one() {
    local prompt="$1"
    shift
    local items=("$@")

    if [[ ${#items[@]} -eq 0 ]]; then
        return 1
    fi

    if command -v fzf >/dev/null 2>&1; then
        printf "%s\n" "${items[@]}" | fzf --height=18 --layout=reverse --border --prompt="$prompt"
    else
        local i
        for i in "${!items[@]}"; do
            printf "%d) %s\n" "$((i+1))" "${items[$i]}"
        done
        local idx
        read -r -p "Choose [1-${#items[@]}]: " idx
        if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >=1 && idx <= ${#items[@]} )); then
            echo "${items[$((idx-1))]}"
        fi
    fi
}

write_module_file() {
    local module_file="$1"
    local module_name="$2"
    local category="$3"

    {
        echo "#!/usr/bin/env bash"
        echo "# CATEGORY: ${category}"
        echo "# MODULE: ${module_name}"
        echo ""
        local i
        for i in "${!CMDS[@]}"; do
            echo "## ${CMDS[$i]}"
            echo "# @desc  ${DESCS[$i]}"
            echo "# @usage ${USAGES[$i]}"
            echo "# @example ${EXAMPLES[$i]}"
            echo "# @genuine $(escape_single_quotes "${GENUINES[$i]}")"
            if ! ak_command_is_multiword "${CMDS[$i]}"; then
                echo "alias ${CMDS[$i]}='$(escape_single_quotes "${GENUINES[$i]}")'"
            fi
            echo ""
        done
    } > "$module_file"

    chmod +x "$module_file"
}

write_doc_file() {
    local doc_file="$1"
    local module_name="$2"
    local title
    title=$(ak_humanize_module_name "$module_name")

    {
        echo "# ${title}"
        echo ""
        echo "Custom module managed by \`ak add\` / \`ak edit\`."
        echo ""
        echo "---"
        echo ""
        echo "## Aliases"
        echo ""
        local i
        for i in "${!CMDS[@]}"; do
            echo "### \`${CMDS[$i]}\`"
            echo "- **Description:** ${DESCS[$i]}"
            echo "- **Usage:** \`${USAGES[$i]}\`"
            echo "- **Example:** \`${EXAMPLES[$i]}\`"
            echo ""
            echo "\`\`\`bash"
            echo "${CMDS[$i]}"
            echo "# Runs: ${GENUINES[$i]}"
            echo "\`\`\`"
            echo ""
        done
        echo "---"
        echo ""
        echo "{{#template ../templates/footer.md module=${title}}}"
    } > "$doc_file"
}

find_cmd_index() {
    local target="$1"
    local i
    for i in "${!CMDS[@]}"; do
        [[ "${CMDS[$i]}" == "$target" ]] && { echo "$i"; return 0; }
    done
    return 1
}

complex_command_menu() {
    local header="$1"
    local lines=()
    lines+=("Command Name     : ${command_name}")
    lines+=("Genuine Command  : ${genuine_cmd}")
    lines+=("Post Parameters  : ${post_params_summary}")
    lines+=("Pre Parameters   : ${pre_params_summary}")
    lines+=("Custom Command   : ${custom_cmd}")
    lines+=("Description      : ${desc}")
    lines+=("Usage            : ${usage}")
    lines+=("Example          : ${example}")
    lines+=("")
    lines+=("[Save]")
    lines+=("[Save & Add Another]")
    lines+=("[Back]")

    printf "%s\n" "${lines[@]}" | fzf --height=95% --layout=reverse --border --prompt='Complex Command > ' --header="$header"
}

clear_complex_command_fields() {
    command_name=""
    custom_cmd=""
    genuine_cmd=""
    desc=""
    usage=""
    example=""
    post_params_summary="(auto from command)"
    pre_params_summary="(auto from command)"
    pre_params_json=""
}

refresh_complex_param_summaries() {
    local posts pres expected actual
    posts=$(ak_complex_param_keys_from_template "$genuine_cmd" post | paste -sd', ' -)
    pres=$(ak_complex_param_keys_from_template "$genuine_cmd" pre | paste -sd', ' -)
    [[ -z "$posts" ]] && posts="none"
    [[ -z "$pres" ]] && pres="none"
    post_params_summary="$posts"
    pre_params_summary="$pres"

    if [[ -n "$pre_params_json" ]] && jq empty >/dev/null 2>&1 <<<"$pre_params_json"; then
        expected=$(ak_complex_param_names_from_template "$genuine_cmd" pre | awk '!seen[$0]++' | sort)
        actual=$(jq -r 'keys[]?' <<<"$pre_params_json" | sort)
        [[ "$expected" == "$actual" ]] || pre_params_json=""
    fi
}

complex_find_cmd_index() {
    local target="$1"
    local i
    for i in "${!C_CMDS[@]}"; do
        [[ "${C_CMDS[$i]}" == "$target" ]] && { echo "$i"; return 0; }
    done
    return 1
}

load_complex_command_state_from_index() {
    local idx="$1"
    command_name="${C_CMDS[$idx]}"
    genuine_cmd="${C_GENUINES[$idx]}"
    custom_cmd="${C_CUSTOMS[$idx]}"
    desc="${C_DESCS[$idx]}"
    usage="${C_USAGES[$idx]}"
    example="${C_EXAMPLES[$idx]}"
    pre_params_json="${C_PREJSONS[$idx]}"
    refresh_complex_param_summaries
}

save_complex_command_state_to_index() {
    local idx="$1"
    C_CMDS[$idx]="$command_name"
    C_GENUINES[$idx]="$genuine_cmd"
    C_CUSTOMS[$idx]="$custom_cmd"
    C_DESCS[$idx]="$desc"
    C_USAGES[$idx]="$usage"
    C_EXAMPLES[$idx]="$example"
    C_PREJSONS[$idx]="$pre_params_json"
}

validate_complex_command_state_or_fail() {
    local original_name="${1:-}"

    [[ -n "$command_name" && -n "$genuine_cmd" && -n "$custom_cmd" && -n "$desc" && -n "$usage" && -n "$example" ]] || {
        form_error="All command fields are required."
        return 1
    }

    if ! ak_validate_single_token_command_name "$command_name"; then
        form_error="Invalid command name."
        return 1
    fi

    if ak_is_reserved_ak_command "$command_name"; then
        form_error="This command name is reserved by ak."
        return 1
    fi

    if [[ "$command_name" != "$original_name" ]] && ak_command_exists_any "$command_name"; then
        form_error="This command name is already registered."
        return 1
    fi

    local i
    for i in "${!C_CMDS[@]}"; do
        [[ "${C_CMDS[$i]}" == "$original_name" ]] && continue
        if [[ "${C_CMDS[$i]}" == "$command_name" ]]; then
            form_error="Duplicate command inside this complex module."
            return 1
        fi
    done

    if [[ -z "$pre_params_json" ]]; then
        pre_params_json=$(ak_complex_render_pre_json_template "$genuine_cmd")
    fi

    if ! jq empty >/dev/null 2>&1 <<<"$pre_params_json"; then
        form_error="Pre-parameters JSON is invalid."
        return 1
    fi

    form_error=""
    return 0
}

load_complex_module_state() {
    local target_module="$1"
    local module_dir="${AK_COMPLEX_MODULE_ROOT}/${target_module}"
    local params_file

    [[ -d "$module_dir" ]] || return 1

    complex_original_module_name="$target_module"
    module_name="$target_module"
    category="complex"
    module_desc=""

    declare -ga C_CMDS=()
    declare -ga C_GENUINES=()
    declare -ga C_CUSTOMS=()
    declare -ga C_DESCS=()
    declare -ga C_USAGES=()
    declare -ga C_EXAMPLES=()
    declare -ga C_PREJSONS=()

    while IFS= read -r params_file; do
        [[ -f "$params_file" ]] || continue
        C_CMDS+=("$(jq -r '.command_name // empty' "$params_file")")
        C_GENUINES+=("$(jq -r '.genuine_command // empty' "$params_file")")
        C_CUSTOMS+=("$(jq -r '.custom_command // empty' "$params_file")")
        C_DESCS+=("$(jq -r '.description // empty' "$params_file")")
        C_USAGES+=("$(jq -r '.usage // empty' "$params_file")")
        C_EXAMPLES+=("$(jq -r '.example // empty' "$params_file")")
        C_PREJSONS+=("$(jq -c '.pre_parameters // {}' "$params_file")")

        if [[ -z "$module_desc" ]]; then
            module_desc=$(jq -r '.module_description // empty' "$params_file")
        fi
        if [[ "$category" == "complex" ]]; then
            category=$(jq -r '.category // "complex"' "$params_file")
        fi
    done < <(find "$module_dir" -mindepth 2 -maxdepth 2 -type f -name 'parameters.json' | sort)

    [[ -n "$module_desc" ]] || module_desc="complex"
    [[ -n "$category" ]] || category="complex"
    return 0
}

write_one_complex_command() {
    local target_module="$1"
    local target_category="$2"
    local target_module_desc="$3"
    local cmd_name="$4"
    local cmd_genuine="$5"
    local cmd_custom="$6"
    local cmd_desc="$7"
    local cmd_usage="$8"
    local cmd_example="$9"
    local cmd_pre_json="${10}"
    local sanitized_fn cmd_dir cmd_file params_file doc_file doc_title post_json

    cmd_dir="${AK_COMPLEX_MODULE_ROOT}/${target_module}/${cmd_name}"
    params_file="${cmd_dir}/parameters.json"
    cmd_file="${cmd_dir}/${cmd_name}.sh"
    doc_file="${AK_COMPLEX_DOC_ROOT}/${target_module}/${cmd_name}.md"
    doc_title=$(ak_humanize_module_name "$target_module")
    sanitized_fn=$(printf "%s" "${target_module}_${cmd_name}" | sed 's/[^a-zA-Z0-9_]/_/g')

    mkdir -p "$cmd_dir" "${AK_COMPLEX_DOC_ROOT}/${target_module}"

    if [[ -z "$cmd_pre_json" ]]; then
        cmd_pre_json=$(ak_complex_render_pre_json_template "$cmd_genuine")
    fi
    post_json=$(ak_complex_param_keys_from_template "$cmd_genuine" post | jq -R . | jq -s .)

    jq -n \
        --arg module_name "$target_module" \
        --arg category "$target_category" \
        --arg module_description "$target_module_desc" \
        --arg command_name "$cmd_name" \
        --arg genuine_command "$cmd_genuine" \
        --arg custom_command "$cmd_custom" \
        --arg description "$cmd_desc" \
        --arg usage "$cmd_usage" \
        --arg example "$cmd_example" \
        --argjson pre_parameters "${cmd_pre_json:-\{\}}" \
        --argjson post_parameters "$post_json" \
        '{module_name:$module_name,category:$category,module_description:$module_description,command_name:$command_name,genuine_command:$genuine_command,custom_command:$custom_command,description:$description,usage:$usage,example:$example,pre_parameters:$pre_parameters,post_parameters:$post_parameters}' > "$params_file"

    {
        echo "#!/usr/bin/env bash"
        echo "# CATEGORY: ${target_category}"
        echo "# MODULE: ${target_module}"
        echo "## ${cmd_name}"
        echo "# @desc  ${cmd_desc}"
        echo "# @usage ${cmd_usage}"
        echo "# @example ${cmd_example}"
        echo "${sanitized_fn}() {"
        echo "    __ak_complex_exec \"${params_file}\" \"\$@\""
        echo "}"
        echo "alias ${cmd_name}='${sanitized_fn}'"
    } > "$cmd_file"

    {
        echo "# ${doc_title} [Complex]"
        echo
        echo "## \`${cmd_name}\`"
        echo "- **Description:** ${cmd_desc}"
        echo "- **Usage:** \`${cmd_usage}\`"
        echo "- **Example:** \`${cmd_example}\`"
        echo "- **Custom Command:** \`${cmd_custom}\`"
        echo "- **Genuine Command:** \`${cmd_genuine}\`"
    } > "$doc_file"

    chmod +x "$cmd_file"
}

save_complex_module_state() {
    local old_module="$1"
    local new_module="$module_name"
    local old_module_dir="${AK_COMPLEX_MODULE_ROOT}/${old_module}"
    local old_doc_dir="${AK_COMPLEX_DOC_ROOT}/${old_module}"
    local new_module_dir="${AK_COMPLEX_MODULE_ROOT}/${new_module}"
    local new_doc_dir="${AK_COMPLEX_DOC_ROOT}/${new_module}"
    local i

    if ! ak_validate_module_name "$new_module"; then
        print_color red "Invalid module name format."
        return 1
    fi
    if ak_is_reserved_ak_command "$new_module"; then
        print_color red "Reserved module name."
        return 1
    fi
    if [[ "$new_module" != "$old_module" ]] && ak_module_exists_any "$new_module"; then
        print_color red "Module name already registered (official/custom/complex)."
        return 1
    fi

    mkdir -p "$new_module_dir" "$new_doc_dir"
    rm -rf "$new_module_dir"/* "$new_doc_dir"/*

    for i in "${!C_CMDS[@]}"; do
        write_one_complex_command \
            "$new_module" "$category" "$module_desc" \
            "${C_CMDS[$i]}" "${C_GENUINES[$i]}" "${C_CUSTOMS[$i]}" \
            "${C_DESCS[$i]}" "${C_USAGES[$i]}" "${C_EXAMPLES[$i]}" "${C_PREJSONS[$i]}"
    done

    if [[ "$new_module" != "$old_module" ]]; then
        rm -rf "$old_module_dir" "$old_doc_dir"
    fi

    ak_write_custom_index
    # shellcheck source=/dev/null
    source /home/zisan/Downloads/aliaskit-tui/core/init.sh >/dev/null 2>&1 || true
    complex_original_module_name="$new_module"
    print_color green "✔ Saved complex module: ${new_module}"
    print_color green "✔ Auto executed: source /home/zisan/Downloads/aliaskit-tui/core/init.sh"
    return 0
}

run_normal_edit_flow() {
    mapfile -t custom_modules < <(ak_collect_custom_module_names)
    if [[ ${#custom_modules[@]} -eq 0 ]]; then
        print_color yellow "No custom modules found. Use 'ak add' first."
        return 0
    fi

    selected_module=$(pick_one "Custom Module > " "${custom_modules[@]}")
    [[ -n "$selected_module" ]] || return 0

    module_file=$(ak_get_custom_module_file_by_name "$selected_module")
    [[ -n "$module_file" ]] || { print_color red "Unable to locate module file."; return 1; }

    base_name=$(basename "$module_file")
    prefix="${base_name%%_*}"

    module_name="$selected_module"
    category=$(grep -m 1 "# CATEGORY:" "$module_file" | sed 's/# CATEGORY:[[:space:]]*//')

    declare -a CMDS=()
    declare -a GENUINES=()
    declare -a DESCS=()
    declare -a USAGES=()
    declare -a EXAMPLES=()

    while IFS=$'\t' read -r c d u e g; do
        [[ -n "$c" ]] || continue
        CMDS+=("$c")
        DESCS+=("$d")
        USAGES+=("$u")
        EXAMPLES+=("$e")
        GENUINES+=("$g")
    done < <(ak_extract_entries_from_module_file "$module_file")

    while true; do
        echo ""
        print_color cyan "Editing module: ${module_name}"
        action=$(pick_one "Edit Action > " \
            "Edit module name" \
            "Edit category" \
            "Add command" \
            "Edit command" \
            "Delete command" \
            "Save and exit" \
            "Delete module" \
            "Cancel")

        case "$action" in
            "Edit module name")
                new_name_raw=$(prompt_with_default "New module name" "$module_name") || continue
                new_name=$(ak_slugify "$new_name_raw")
                if ! ak_validate_module_name "$new_name"; then
                    print_color red "Invalid module name format."
                    continue
                fi
                if ak_is_reserved_ak_command "$new_name"; then
                    print_color red "Reserved name."
                    continue
                fi
                if [[ "$new_name" != "$module_name" ]] && ak_module_exists_any "$new_name"; then
                    print_color red "Module name already registered (official/custom)."
                    continue
                fi
                module_name="$new_name"
                ;;
            "Edit category")
                category=$(prompt_with_default "Category" "$category") || continue
                ;;
            "Add command")
                while true; do
                    cmd=$(prompt_with_default "Custom command" "") || { print_color yellow "Cancelled adding command."; break; }
                    cmd=$(normalize_command_input "$cmd")
                    [[ -n "$cmd" ]] || { print_color red "Command cannot be empty."; continue; }
                    if ! ak_validate_command_name "$cmd"; then
                        print_color red "Invalid command format."
                        continue
                    fi
                    if ak_is_reserved_ak_command "$cmd"; then
                        print_color red "Reserved command."
                        continue
                    fi
                    if ak_command_exists_any "$cmd" || printf "%s\n" "${CMDS[@]}" | grep -qx "$cmd"; then
                        print_color red "Command already registered (official/custom)."
                        continue
                    fi
                    break
                done
                [[ -n "$cmd" ]] || continue
                genuine=$(prompt_with_default "Genuine command" "") || continue
                desc=$(prompt_with_default "Description" "") || continue
                usage=$(prompt_with_default "Usage" "$cmd") || continue
                example=$(prompt_with_default "Example" "$cmd") || continue
                CMDS+=("$cmd")
                GENUINES+=("$genuine")
                DESCS+=("$desc")
                USAGES+=("$usage")
                EXAMPLES+=("$example")
                ;;
            "Edit command")
                if [[ ${#CMDS[@]} -eq 0 ]]; then
                    print_color yellow "No command to edit."
                    continue
                fi
                selected_cmd=$(pick_one "Command > " "${CMDS[@]}")
                [[ -n "$selected_cmd" ]] || continue
                idx=$(find_cmd_index "$selected_cmd") || continue

                new_cmd=$(prompt_with_default "Custom command" "${CMDS[$idx]}") || continue
                new_cmd=$(normalize_command_input "$new_cmd")
                if [[ "$new_cmd" != "${CMDS[$idx]}" ]]; then
                    if ! ak_validate_command_name "$new_cmd"; then
                        print_color red "Invalid command format."
                        continue
                    fi
                    if ak_is_reserved_ak_command "$new_cmd"; then
                        print_color red "Reserved command."
                        continue
                    fi
                    if ak_command_exists_any "$new_cmd" || printf "%s\n" "${CMDS[@]}" | grep -qx "$new_cmd"; then
                        print_color red "Command already registered (official/custom)."
                        continue
                    fi
                    CMDS[$idx]="$new_cmd"
                fi

                GENUINES[$idx]=$(prompt_with_default "Genuine command" "${GENUINES[$idx]}") || continue
                DESCS[$idx]=$(prompt_with_default "Description" "${DESCS[$idx]}") || continue
                USAGES[$idx]=$(prompt_with_default "Usage" "${USAGES[$idx]}") || continue
                EXAMPLES[$idx]=$(prompt_with_default "Example" "${EXAMPLES[$idx]}") || continue
                ;;
            "Delete command")
                if [[ ${#CMDS[@]} -eq 0 ]]; then
                    print_color yellow "No command to delete."
                    continue
                fi
                selected_cmd=$(pick_one "Delete Command > " "${CMDS[@]}")
                [[ -n "$selected_cmd" ]] || continue
                idx=$(find_cmd_index "$selected_cmd") || continue

                unset 'CMDS[idx]' 'GENUINES[idx]' 'DESCS[idx]' 'USAGES[idx]' 'EXAMPLES[idx]'
                CMDS=("${CMDS[@]}")
                GENUINES=("${GENUINES[@]}")
                DESCS=("${DESCS[@]}")
                USAGES=("${USAGES[@]}")
                EXAMPLES=("${EXAMPLES[@]}")
                ;;
            "Save and exit")
                if [[ ${#CMDS[@]} -eq 0 ]]; then
                    print_color red "Module must contain at least one command."
                    continue
                fi

                conflict_found=0
                for cmd in "${CMDS[@]}"; do
                    if ak_command_exists_official "$cmd"; then
                        print_color red "'${cmd}' is already registered in official list. Change it before saving."
                        conflict_found=1
                    fi
                done
                (( conflict_found == 1 )) && continue

                new_module_file="${AK_CUSTOM_MODULE_DIR}/${prefix}_${module_name}.sh"
                new_doc_file="${AK_CUSTOM_DOC_MODULE_DIR}/${prefix}_${module_name}.md"

                write_module_file "$new_module_file" "$module_name" "$category"
                write_doc_file "$new_doc_file" "$module_name"

                if [[ "$new_module_file" != "$module_file" && -f "$module_file" ]]; then
                    rm -f "$module_file"
                fi
                old_doc_file="${AK_CUSTOM_DOC_MODULE_DIR}/${prefix}_${selected_module}.md"
                if [[ "$new_doc_file" != "$old_doc_file" && -f "$old_doc_file" ]]; then
                    rm -f "$old_doc_file"
                fi

                ak_write_custom_index
                # shellcheck source=/dev/null
                source /home/zisan/Downloads/aliaskit-tui/core/init.sh >/dev/null 2>&1 || true
                print_color green "✔ Saved module: ${module_name}"
                print_color green "✔ Auto executed: source /home/zisan/Downloads/aliaskit-tui/core/init.sh"
                return 0
                ;;
            "Delete module")
                read -r -p "Type YES to delete module '${module_name}': " confirm
                if [[ "$confirm" =~ ^([Yy][Ee][Ss]|[Yy])$ ]]; then
                    rm -f "$module_file" "${AK_CUSTOM_DOC_MODULE_DIR}/${prefix}_${selected_module}.md" "${AK_CUSTOM_DOC_MODULE_DIR}/${prefix}_${module_name}.md"
                    ak_write_custom_index
                    # shellcheck source=/dev/null
                    source /home/zisan/Downloads/aliaskit-tui/core/init.sh >/dev/null 2>&1 || true
                    print_color green "✔ Module deleted: ${module_name}"
                    print_color green "✔ Auto executed: source /home/zisan/Downloads/aliaskit-tui/core/init.sh"
                    return 0
                else
                    print_color yellow "Delete cancelled."
                fi
                ;;
            "Cancel"|"")
                print_color yellow "Cancelled. No changes saved."
                return 0
                ;;
        esac
    done
}

run_complex_command_editor() {
    local mode="$1"
    local idx="${2:-}"
    local original_name=""
    form_error=""

    if [[ "$mode" == "edit" ]]; then
        load_complex_command_state_from_index "$idx"
        original_name="$command_name"
    else
        clear_complex_command_fields
    fi

    while true; do
        refresh_complex_param_summaries
        header="ak edit complex — Command Setup\n\nModule: ${module_name}"
        if [[ "$mode" == "edit" ]]; then
            header+="\nEditing: ${original_name}"
        else
            header+="\nAdding new complex command"
        fi
        [[ -n "$form_error" ]] && header+="\n\n⚠ ${form_error}"

        selected=$(complex_command_menu "$header") || return 1
        case "$selected" in
            "Command Name"* ) value=$(prompt_with_default "Command Name" "$command_name") || continue; [[ -n "$value" ]] && command_name="$value"; form_error="" ;;
            "Genuine Command"* ) value=$(prompt_with_default "Genuine Command" "$genuine_cmd") || continue; [[ -n "$value" ]] && genuine_cmd="$value"; refresh_complex_param_summaries; form_error="" ;;
            "Post Parameters"* ) form_error="Post parameters are auto-detected from Genuine Command." ;;
            "Pre Parameters"* )
                edited=$(ak_complex_edit_pre_params_tui "$pre_params_json" "$genuine_cmd")
                status=$?
                if [[ $status -eq 0 ]]; then
                    pre_params_json="$edited"
                    form_error=""
                else
                    form_error="Pre-parameter editing cancelled."
                fi ;;
            "Custom Command"* ) value=$(prompt_with_default "Custom Command" "$custom_cmd") || continue; [[ -n "$value" ]] && custom_cmd="$value"; form_error="" ;;
            "Description"* ) value=$(prompt_with_default "Description" "$desc") || continue; [[ -n "$value" ]] && desc="$value"; form_error="" ;;
            "Usage"* ) value=$(prompt_with_default "Usage" "$usage") || continue; [[ -n "$value" ]] && usage="$value"; form_error="" ;;
            "Example"* ) value=$(prompt_with_default "Example" "$example") || continue; [[ -n "$value" ]] && example="$value"; form_error="" ;;
            "[Save]")
                if validate_complex_command_state_or_fail "$original_name"; then
                    if [[ "$mode" == "edit" ]]; then
                        save_complex_command_state_to_index "$idx"
                    else
                        C_CMDS+=("$command_name")
                        C_GENUINES+=("$genuine_cmd")
                        C_CUSTOMS+=("$custom_cmd")
                        C_DESCS+=("$desc")
                        C_USAGES+=("$usage")
                        C_EXAMPLES+=("$example")
                        C_PREJSONS+=("$pre_params_json")
                    fi
                    return 0
                fi ;;
            "[Save & Add Another]")
                if validate_complex_command_state_or_fail "$original_name"; then
                    if [[ "$mode" == "edit" ]]; then
                        save_complex_command_state_to_index "$idx"
                        clear_complex_command_fields
                        mode="add"
                        original_name=""
                        idx=""
                    else
                        C_CMDS+=("$command_name")
                        C_GENUINES+=("$genuine_cmd")
                        C_CUSTOMS+=("$custom_cmd")
                        C_DESCS+=("$desc")
                        C_USAGES+=("$usage")
                        C_EXAMPLES+=("$example")
                        C_PREJSONS+=("$pre_params_json")
                        clear_complex_command_fields
                    fi
                    form_error=""
                fi ;;
            "[Back]"|"")
                return 1
                ;;
        esac
    done
}

run_complex_edit_flow() {
    local selected_module action selected_cmd idx
    mapfile -t complex_modules < <(ak_collect_complex_module_names)
    if [[ ${#complex_modules[@]} -eq 0 ]]; then
        print_color yellow "No complex modules found. Use 'ak add complex' first."
        return 0
    fi

    selected_module=$(pick_one "Complex Module > " "${complex_modules[@]}")
    [[ -n "$selected_module" ]] || return 0
    load_complex_module_state "$selected_module" || { print_color red "Unable to load complex module."; return 1; }

    while true; do
        echo ""
        print_color cyan "Editing complex module: ${module_name}"
        action=$(pick_one "Complex Action > " \
            "Edit module name" \
            "Edit category" \
            "Edit description" \
            "Add complex command" \
            "Edit complex command" \
            "Delete complex command" \
            "Save and exit" \
            "Delete module" \
            "Cancel")

        case "$action" in
            "Edit module name")
                new_name_raw=$(prompt_with_default "New module name" "$module_name") || continue
                new_name=$(ak_slugify "$new_name_raw")
                if ! ak_validate_module_name "$new_name"; then
                    print_color red "Invalid module name format."
                    continue
                fi
                if ak_is_reserved_ak_command "$new_name"; then
                    print_color red "Reserved name."
                    continue
                fi
                if [[ "$new_name" != "$complex_original_module_name" ]] && ak_module_exists_any "$new_name"; then
                    print_color red "Module name already registered (official/custom/complex)."
                    continue
                fi
                module_name="$new_name"
                ;;
            "Edit category")
                category=$(prompt_with_default "Category" "$category") || continue
                ;;
            "Edit description")
                module_desc=$(prompt_with_default "Description" "$module_desc") || continue
                ;;
            "Add complex command")
                run_complex_command_editor add || true
                ;;
            "Edit complex command")
                if [[ ${#C_CMDS[@]} -eq 0 ]]; then
                    print_color yellow "No complex command to edit."
                    continue
                fi
                selected_cmd=$(pick_one "Complex Command > " "${C_CMDS[@]}")
                [[ -n "$selected_cmd" ]] || continue
                idx=$(complex_find_cmd_index "$selected_cmd") || continue
                run_complex_command_editor edit "$idx" || true
                ;;
            "Delete complex command")
                if [[ ${#C_CMDS[@]} -eq 0 ]]; then
                    print_color yellow "No complex command to delete."
                    continue
                fi
                selected_cmd=$(pick_one "Delete Complex Command > " "${C_CMDS[@]}")
                [[ -n "$selected_cmd" ]] || continue
                idx=$(complex_find_cmd_index "$selected_cmd") || continue
                unset 'C_CMDS[idx]' 'C_GENUINES[idx]' 'C_CUSTOMS[idx]' 'C_DESCS[idx]' 'C_USAGES[idx]' 'C_EXAMPLES[idx]' 'C_PREJSONS[idx]'
                C_CMDS=("${C_CMDS[@]}")
                C_GENUINES=("${C_GENUINES[@]}")
                C_CUSTOMS=("${C_CUSTOMS[@]}")
                C_DESCS=("${C_DESCS[@]}")
                C_USAGES=("${C_USAGES[@]}")
                C_EXAMPLES=("${C_EXAMPLES[@]}")
                C_PREJSONS=("${C_PREJSONS[@]}")
                print_color green "✔ Removed complex command: ${selected_cmd}"
                ;;
            "Save and exit")
                save_complex_module_state "$complex_original_module_name" && return 0
                ;;
            "Delete module")
                read -r -p "Type YES to delete complex module '${module_name}': " confirm
                if [[ "$confirm" =~ ^([Yy][Ee][Ss]|[Yy])$ ]]; then
                    rm -rf "${AK_COMPLEX_MODULE_ROOT}/${complex_original_module_name}" "${AK_COMPLEX_DOC_ROOT}/${complex_original_module_name}" "${AK_COMPLEX_MODULE_ROOT}/${module_name}" "${AK_COMPLEX_DOC_ROOT}/${module_name}"
                    ak_write_custom_index
                    # shellcheck source=/dev/null
                    source /home/zisan/Downloads/aliaskit-tui/core/init.sh >/dev/null 2>&1 || true
                    print_color green "✔ Complex module deleted: ${module_name}"
                    print_color green "✔ Auto executed: source /home/zisan/Downloads/aliaskit-tui/core/init.sh"
                    return 0
                else
                    print_color yellow "Delete cancelled."
                fi
                ;;
            "Cancel"|"")
                print_color yellow "Cancelled. No changes saved."
                return 0
                ;;
        esac
    done
}

ak_registry_bootstrap

target_type=$(pick_one "Edit Target > " "Normal custom module" "Complex custom module")
case "$target_type" in
    "Normal custom module")
        run_normal_edit_flow
        ;;
    "Complex custom module")
        run_complex_edit_flow
        ;;
    *)
        exit 0
        ;;
esac
