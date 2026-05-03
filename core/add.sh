#!/usr/bin/env bash

# core/add.sh - Normal + complex custom command wizard

AK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${AK_ROOT}/core/registry.sh"
# shellcheck source=/dev/null
source "${AK_ROOT}/core/complex.sh"

MODE="${1:-normal}"

print_color() {
    local color="$1"
    local text="$2"
    case "$color" in
        green) echo -e "\033[32m${text}\033[0m" ;;
        yellow) echo -e "\033[33m${text}\033[0m" ;;
        red) echo -e "\033[31m${text}\033[0m" ;;
        cyan) echo -e "\033[36m${text}\033[0m" ;;
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

input_box() {
    local label="$1"
    local header="$2"
    local initial="${3:-}"
    local out value

    if ! command -v fzf >/dev/null 2>&1; then
        read -r -p "$label: " value
        printf "%s" "$value"
        return 0
    fi

    out=$(printf '\n' | fzf \
        --height=95% \
        --layout=reverse \
        --border \
        --phony \
        --prompt="${label} > " \
        --header="$header" \
        --bind='enter:accept' \
        --print-query \
        --query="$initial") || return 1

    value=$(printf "%s\n" "$out" | awk 'NF{print; exit}')
    printf "%s" "$value"
}

normal_form_menu() {
    local header="$1"
    local lines=()
    lines+=("Module Name      : ${module_name}")
    lines+=("Category         : ${category}")
    lines+=("Custom Command   : ${custom_cmd}")
    lines+=("Genuine Command  : ${genuine_cmd}")
    lines+=("Description      : ${desc}")
    lines+=("Usage            : ${usage}")
    lines+=("Example          : ${example}")
    lines+=("")
    lines+=("[Save]")
    lines+=("[Save & Add Another]")
    lines+=("[Cancel]")

    if command -v fzf >/dev/null 2>&1; then
        printf "%s\n" "${lines[@]}" | fzf --height=95% --layout=reverse --border --prompt='Form > ' --header="$header"
    else
        printf "%s\n" "[Cancel]"
    fi
}

complex_module_menu() {
    local header="$1"
    local lines=()
    lines+=("Module Name      : ${module_name}")
    lines+=("Category         : ${category}")
    lines+=("Description      : ${module_desc}")
    lines+=("")
    lines+=("[Save & Continue]")
    lines+=("[Save & Exit]")
    lines+=("[Exit]")

    printf "%s\n" "${lines[@]}" | fzf --height=95% --layout=reverse --border --prompt='Complex Module > ' --header="$header"
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
    lines+=("[Save & Continue]")
    lines+=("[Save & Exit]")
    lines+=("[Exit]")

    printf "%s\n" "${lines[@]}" | fzf --height=95% --layout=reverse --border --prompt='Complex Command > ' --header="$header"
}

clear_command_fields() {
    custom_cmd=""
    genuine_cmd=""
    desc=""
    usage=""
    example=""
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

append_current_command_or_fail() {
    [[ -n "$custom_cmd" && -n "$genuine_cmd" && -n "$desc" && -n "$usage" && -n "$example" ]] || {
        form_error="All fields are required."
        return 1
    }

    if ! ak_validate_command_name "$custom_cmd"; then
        form_error="Invalid command format."
        return 1
    fi
    if ak_is_reserved_ak_command "$custom_cmd"; then
        form_error="This command is reserved by ak."
        return 1
    fi
    if ak_command_exists_any "$custom_cmd"; then
        form_error="This command is already registered (official/custom)."
        return 1
    fi
    if printf "%s\n" "${CMDS[@]}" | grep -qx "$custom_cmd"; then
        form_error="Duplicate command in this module."
        return 1
    fi

    CMDS+=("$custom_cmd")
    GENUINES+=("$genuine_cmd")
    DESCS+=("$desc")
    USAGES+=("$usage")
    EXAMPLES+=("$example")
    return 0
}

write_module_and_docs() {
    local prefix prefix_padded module_file doc_file doc_title
    prefix=$(ak_get_next_custom_module_number)
    printf -v prefix_padded "%02d" "$prefix"

    module_file="${AK_CUSTOM_MODULE_DIR}/${prefix_padded}_${module_name}.sh"
    doc_file="${AK_CUSTOM_DOC_MODULE_DIR}/${prefix_padded}_${module_name}.md"
    doc_title=$(ak_humanize_module_name "$module_name")

    {
        echo "#!/usr/bin/env bash"
        echo "# CATEGORY: ${category}"
        echo "# MODULE: ${module_name}"
        echo ""
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

    {
        echo "# ${doc_title}"
        echo ""
        echo "Custom module created with \`ak add\`."
        echo ""
        echo "---"
        echo ""
        echo "## Aliases"
        echo ""
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
        echo "{{#template ../templates/footer.md module=${doc_title}}}"
    } > "$doc_file"

    chmod +x "$module_file"
    ak_write_custom_index
    # shellcheck source=/dev/null
    source /home/zisan/Downloads/aliaskit-tui/core/init.sh >/dev/null 2>&1 || true
    print_color green "✔ Custom module created: ${module_name}"
    echo "- Module file: ${module_file}"
    echo "- Doc file:    ${doc_file}"
    print_color green "✔ Auto executed: source /home/$(whoami)/.aliaskit/core/init.sh"
}

validate_complex_module_or_fail() {
    [[ -n "$module_name" && -n "$category" && -n "$module_desc" ]] || {
        form_error="All module fields are required."
        return 1
    }
    if ! ak_validate_module_name "$module_name"; then
        form_error="Invalid module name."
        return 1
    fi
    if ak_is_reserved_ak_command "$module_name"; then
        form_error="This module name is reserved by ak."
        return 1
    fi
    if ak_module_exists_official "$module_name" || ak_module_exists_custom "$module_name"; then
        form_error="This module name is already registered (official/normal custom)."
        return 1
    fi
    return 0
}

ensure_complex_module_dirs() {
    mkdir -p "${AK_COMPLEX_MODULE_ROOT}/${module_name}" "${AK_COMPLEX_DOC_ROOT}/${module_name}"
}

write_complex_command_files() {
    local sanitized_fn cmd_dir cmd_file params_file doc_file doc_title post_json
    cmd_dir="${AK_COMPLEX_MODULE_ROOT}/${module_name}/${command_name}"
    params_file="${cmd_dir}/parameters.json"
    cmd_file="${cmd_dir}/${command_name}.sh"
    doc_file="${AK_COMPLEX_DOC_ROOT}/${module_name}/${command_name}.md"
    doc_title=$(ak_humanize_module_name "$module_name")
    sanitized_fn=$(printf "%s" "${module_name}_${command_name}" | sed 's/[^a-zA-Z0-9_]/_/g')

    mkdir -p "$cmd_dir"

    if [[ -z "$pre_params_json" ]]; then
        pre_params_json=$(ak_complex_render_pre_json_template "$genuine_cmd")
    fi
    post_json=$(ak_complex_param_keys_from_template "$genuine_cmd" post | jq -R . | jq -s .)

    jq -n \
        --arg module_name "$module_name" \
        --arg category "$category" \
        --arg module_description "$module_desc" \
        --arg command_name "$command_name" \
        --arg genuine_command "$genuine_cmd" \
        --arg custom_command "$custom_cmd" \
        --arg description "$desc" \
        --arg usage "$usage" \
        --arg example "$example" \
        --argjson pre_parameters "${pre_params_json:-\{\}}" \
        --argjson post_parameters "$post_json" \
        '{module_name:$module_name,category:$category,module_description:$module_description,command_name:$command_name,genuine_command:$genuine_command,custom_command:$custom_command,description:$description,usage:$usage,example:$example,pre_parameters:$pre_parameters,post_parameters:$post_parameters}' > "$params_file"

    {
        echo "#!/usr/bin/env bash"
        echo "# CATEGORY: ${category}"
        echo "# MODULE: ${module_name}"
        echo "## ${command_name}"
        echo "# @desc  ${desc}"
        echo "# @usage ${usage}"
        echo "# @example ${example}"
        echo "${sanitized_fn}() {"
        echo "    __ak_complex_exec \"${params_file}\" \"\$@\""
        echo "}"
        echo "alias ${command_name}='${sanitized_fn}'"
    } > "$cmd_file"

    {
        echo "# ${doc_title} [Complex]"
        echo
        echo "## \`${command_name}\`"
        echo "- **Description:** ${desc}"
        echo "- **Usage:** \`${usage}\`"
        echo "- **Example:** \`${example}\`"
        echo "- **Custom Command:** \`${custom_cmd}\`"
        echo "- **Genuine Command:** \`${genuine_cmd}\`"
    } > "$doc_file"

    chmod +x "$cmd_file"
}

validate_complex_command_or_fail() {
    [[ -n "$command_name" && -n "$genuine_cmd" && -n "$custom_cmd" && -n "$desc" && -n "$usage" && -n "$example" ]] || {
        form_error="All command fields are required."
        return 1
    }
    if ! ak_validate_single_token_command_name "$command_name"; then
        form_error="Invalid command name."
        return 1
    fi
    if ak_is_reserved_ak_command "$command_name" || ak_command_exists_any "$command_name"; then
        form_error="This command name is already reserved/registered."
        return 1
    fi
    if [[ -e "${AK_COMPLEX_MODULE_ROOT}/${module_name}/${command_name}" ]]; then
        form_error="This complex command already exists in the module."
        return 1
    fi
    return 0
}

run_normal_flow() {
    ak_registry_bootstrap
    declare -a CMDS=()
    declare -a GENUINES=()
    declare -a DESCS=()
    declare -a USAGES=()
    declare -a EXAMPLES=()

    module_name=""
    category=""
    clear_command_fields
    form_error=""

    while true; do
        form_header="ak add — Single Form Wizard\n\nUse ↑↓ to navigate, Enter to edit/select."
        form_header+="\nCommands queued: ${#CMDS[@]}"
        [[ -n "$form_error" ]] && form_header+="\n\n⚠ ${form_error}"

        selected=$(normal_form_menu "$form_header") || exit 0
        case "$selected" in
            "Module Name"* ) value=$(input_box "Module Name" "Enter module name" "$module_name") || continue; [[ -n "$value" ]] && module_name=$(ak_slugify "$value"); form_error="" ;;
            "Category"* ) value=$(input_box "Category" "Enter category/title" "$category") || continue; [[ -n "$value" ]] && category="$value"; form_error="" ;;
            "Custom Command"* ) value=$(input_box "Custom Command" "Enter custom command (single or multi-word, e.g. bots up)" "$custom_cmd") || continue; [[ -n "$value" ]] && custom_cmd=$(normalize_command_input "$value"); form_error="" ;;
            "Genuine Command"* ) value=$(input_box "Genuine Command" "Enter genuine command" "$genuine_cmd") || continue; [[ -n "$value" ]] && genuine_cmd="$value"; form_error="" ;;
            "Description"* ) value=$(input_box "Description" "Enter description" "$desc") || continue; [[ -n "$value" ]] && desc="$value"; form_error="" ;;
            "Usage"* ) value=$(input_box "Usage" "Enter usage" "$usage") || continue; [[ -n "$value" ]] && usage="$value"; form_error="" ;;
            "Example"* ) value=$(input_box "Example" "Enter example" "$example") || continue; [[ -n "$value" ]] && example="$value"; form_error="" ;;
            "[Save & Add Another]")
                [[ -n "$module_name" && -n "$category" ]] || { form_error="All fields are required."; continue; }
                if ! ak_validate_module_name "$module_name"; then form_error="Invalid module name."; continue; fi
                if ak_is_reserved_ak_command "$module_name"; then form_error="This module name is reserved by ak."; continue; fi
                if ak_module_exists_any "$module_name"; then form_error="This module name is already registered (official/custom)."; continue; fi
                if append_current_command_or_fail; then clear_command_fields; form_error=""; fi ;;
            "[Save]")
                [[ -n "$module_name" && -n "$category" ]] || { form_error="All fields are required."; continue; }
                if ! ak_validate_module_name "$module_name"; then form_error="Invalid module name."; continue; fi
                if ak_is_reserved_ak_command "$module_name"; then form_error="This module name is reserved by ak."; continue; fi
                if ak_module_exists_any "$module_name"; then form_error="This module name is already registered (official/custom)."; continue; fi
                if append_current_command_or_fail; then write_module_and_docs; exit 0; fi ;;
            "[Cancel]"|"") exit 0 ;;
        esac
    done
}

run_complex_flow() {
    ak_registry_bootstrap
    module_name=""
    category=""
    module_desc=""
    clear_complex_command_fields
    form_error=""
    current_step="module"

    while true; do
        if [[ "$current_step" == "module" ]]; then
            header="ak add complex — Module Setup\n\nCreate a complex module container first."
            [[ -n "$form_error" ]] && header+="\n\n⚠ ${form_error}"
            selected=$(complex_module_menu "$header") || exit 0
            case "$selected" in
                "Module Name"* ) value=$(input_box "Module Name" "Enter module name" "$module_name") || continue; [[ -n "$value" ]] && module_name=$(ak_slugify "$value"); form_error="" ;;
                "Category"* ) value=$(input_box "Category" "Enter category" "$category") || continue; [[ -n "$value" ]] && category="$value"; form_error="" ;;
                "Description"* ) value=$(input_box "Description" "Enter module description" "$module_desc") || continue; [[ -n "$value" ]] && module_desc="$value"; form_error="" ;;
                "[Save & Continue]")
                    if validate_complex_module_or_fail; then ensure_complex_module_dirs; clear_complex_command_fields; current_step="command"; form_error=""; fi ;;
                "[Save & Exit]")
                    if validate_complex_module_or_fail; then ensure_complex_module_dirs; ak_write_custom_index; source /home/zisan/Downloads/aliaskit-tui/core/init.sh >/dev/null 2>&1 || true; print_color green "✔ Complex module created: ${module_name}"; exit 0; fi ;;
                "[Exit]"|"") exit 0 ;;
            esac
        else
            refresh_complex_param_summaries
            header="ak add complex — Command Setup\n\nModule: ${module_name}"
            [[ -n "$form_error" ]] && header+="\n\n⚠ ${form_error}"
            selected=$(complex_command_menu "$header") || exit 0
            case "$selected" in
                "Command Name"* ) value=$(input_box "Command Name" "Enter complex command name" "$command_name") || continue; [[ -n "$value" ]] && command_name=$(normalize_command_input "$value"); form_error="" ;;
                "Genuine Command"* ) value=$(input_box "Genuine Command" "Use [] for post params and {} for pre params" "$genuine_cmd") || continue; [[ -n "$value" ]] && genuine_cmd="$value"; refresh_complex_param_summaries; form_error="" ;;
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
                "Custom Command"* ) value=$(input_box "Custom Command" "Example: extract-audio [input.mp4] [output] {type}" "$custom_cmd") || continue; [[ -n "$value" ]] && custom_cmd="$value"; form_error="" ;;
                "Description"* ) value=$(input_box "Description" "Enter description" "$desc") || continue; [[ -n "$value" ]] && desc="$value"; form_error="" ;;
                "Usage"* ) value=$(input_box "Usage" "Enter usage" "$usage") || continue; [[ -n "$value" ]] && usage="$value"; form_error="" ;;
                "Example"* ) value=$(input_box "Example" "Enter example" "$example") || continue; [[ -n "$value" ]] && example="$value"; form_error="" ;;
                "[Save & Continue]")
                    if validate_complex_command_or_fail; then write_complex_command_files; ak_write_custom_index; source /home/zisan/Downloads/aliaskit-tui/core/init.sh >/dev/null 2>&1 || true; clear_complex_command_fields; form_error=""; fi ;;
                "[Save & Exit]")
                    if validate_complex_command_or_fail; then write_complex_command_files; ak_write_custom_index; source /home/zisan/Downloads/aliaskit-tui/core/init.sh >/dev/null 2>&1 || true; print_color green "✔ Complex command created: ${command_name} (${module_name})"; exit 0; fi ;;
                "[Exit]"|"") exit 0 ;;
            esac
        fi
    done
}

if [[ "$MODE" == "complex" ]]; then
    run_complex_flow
else
    run_normal_flow
fi
