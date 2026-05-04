#!/usr/bin/env bash

AK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${AK_ROOT}/core/registry.sh"
source "${AK_ROOT}/core/sync_registry.sh"

print_color() {
    case "$1" in
        green) echo -e "\033[32m$2\033[0m" ;;
        yellow) echo -e "\033[33m$2\033[0m" ;;
        red) echo -e "\033[31m$2\033[0m" ;;
        cyan) echo -e "\033[36m$2\033[0m" ;;
        bold) echo -e "\033[1m$2\033[0m" ;;
        *) echo "$2" ;;
    esac
}

pick_package() {
    local rows
    rows=$(ak_sync_list_packages | awk -F'\t' '{printf "%s\t%s\tlast sync: %s\n", $1, $2, $3}')
    [[ -n "$rows" ]] || return 1

    if command -v fzf >/dev/null 2>&1; then
        printf '%s\n' "$rows" | fzf --height=90% --layout=reverse --border --prompt='Sync Package > ' --header='Select a pulled package to sync'
    else
        printf '%s\n' "$rows" | head -n1
    fi
}

conflict_picker() {
    local rows="$1"
    [[ -n "$rows" ]] || return 0

    if command -v fzf >/dev/null 2>&1; then
        printf '%s\n' "$rows" | fzf --multi --height=95% --layout=reverse --border \
            --prompt='Replace Conflicts > ' \
            --header=$'Select conflicting entries you want to REPLACE\nUnselected conflicts will be skipped.' \
            --preview 'printf "%s\n" {}'
    else
        printf ''
    fi
}

ak_registry_bootstrap
ak_sync_init_state_files || exit 1
ak_sync_require_tool jq || exit 1

selection=$(pick_package) || {
    print_color yellow "No pulled packages found. Use 'ak pull <repo>' first."
    exit 0
}

package_name=$(printf '%s' "$selection" | cut -f1)
repo_ref=$(ak_sync_get_package_field "$package_name" repo)
package_dir=$(ak_sync_get_package_field "$package_name" package_dir)
source_custom_dir="${package_dir}/custom"

[[ -d "$source_custom_dir" ]] || {
    print_color red "Selected package source directory is missing. Pull again first."
    exit 1
}

declare -a imported_items=() replaced_items=() skipped_items=() conflict_rows=()
declare -A replace_selected=()

while IFS= read -r src_module_file; do
    [[ -f "$src_module_file" ]] || continue
    module_meta=$(ak_sync_read_normal_module_meta "$src_module_file")
    src_module_name=$(printf '%s' "$module_meta" | cut -f1)
    src_category=$(printf '%s' "$module_meta" | cut -f2)

    if dest_module_file=$(ak_get_custom_module_file_by_name "$src_module_name"); then
        while IFS=$'\t' read -r src_cmd src_desc src_usage src_example src_genuine; do
            [[ -n "$src_cmd" ]] || continue
            if ak_command_exists_custom "$src_cmd" || ak_command_exists_complex "$src_cmd" || ak_command_exists_official "$src_cmd"; then
                conflict_rows+=("normal|${src_module_name}|${src_cmd}|${src_desc}|${src_usage}|${src_example}|${src_genuine}")
            fi
        done < <(ak_sync_extract_normal_module_entries "$src_module_file")
    fi
done < <(find "$source_custom_dir/modules" -maxdepth 1 -type f -name '*.sh' | sort)

while IFS= read -r src_cmd_file; do
    [[ -f "$src_cmd_file" ]] || continue
    complex_module=$(basename "$(dirname "$(dirname "$src_cmd_file")")")
    complex_cmd=$(basename "$src_cmd_file" .sh)
    if ak_command_exists_complex "$complex_cmd" || ak_command_exists_custom "$complex_cmd" || ak_command_exists_official "$complex_cmd"; then
        conflict_rows+=("complex|${complex_module}|${complex_cmd}|-|-|-|-")
    fi
done < <(find "$source_custom_dir/modules/complex" -mindepth 2 -maxdepth 2 -type f -name '*.sh' 2>/dev/null | sort)

if [[ ${#conflict_rows[@]} -gt 0 ]]; then
    display_rows=$(printf '%s\n' "${conflict_rows[@]}" | awk -F'|' '{printf "[%s] %s :: %s\n", $1, $2, $3}')
    selected_rows=$(conflict_picker "$display_rows")
    while IFS= read -r picked; do
        [[ -n "$picked" ]] || continue
        key=$(printf '%s' "$picked" | sed -E 's/^\[([^]]+)\] ([^ ]+) :: (.+)$/\1|\2|\3/')
        replace_selected["$key"]=1
    done <<< "$selected_rows"
fi

while IFS= read -r src_module_file; do
    [[ -f "$src_module_file" ]] || continue
    module_meta=$(ak_sync_read_normal_module_meta "$src_module_file")
    src_module_name=$(printf '%s' "$module_meta" | cut -f1)
    src_category=$(printf '%s' "$module_meta" | cut -f2)

    if dest_module_file=$(ak_get_custom_module_file_by_name "$src_module_name"); then
        prefix=$(basename "$dest_module_file")
        prefix="${prefix%%_*}"
        dest_doc_file=$(ak_sync_find_custom_doc_file "$src_module_name")

        declare -a dest_cmds=() dest_genuines=() dest_descs=() dest_usages=() dest_examples=()
        while IFS=$'\t' read -r c d u e g; do
            [[ -n "$c" ]] || continue
            dest_cmds+=("$c"); dest_descs+=("$d"); dest_usages+=("$u"); dest_examples+=("$e"); dest_genuines+=("$g")
        done < <(ak_extract_entries_from_module_file "$dest_module_file")

        while IFS=$'\t' read -r src_cmd src_desc src_usage src_example src_genuine; do
            [[ -n "$src_cmd" ]] || continue
            replace_key="normal|${src_module_name}|${src_cmd}"
            found_idx=''
            for i in "${!dest_cmds[@]}"; do
                [[ "${dest_cmds[$i]}" == "$src_cmd" ]] && found_idx="$i" && break
            done

            if [[ -n "$found_idx" ]]; then
                if [[ -n "${replace_selected[$replace_key]:-}" ]]; then
                    dest_cmds[$found_idx]="$src_cmd"
                    dest_descs[$found_idx]="$src_desc"
                    dest_usages[$found_idx]="$src_usage"
                    dest_examples[$found_idx]="$src_example"
                    dest_genuines[$found_idx]="$src_genuine"
                    replaced_items+=("normal:${src_module_name}:${src_cmd}")
                else
                    skipped_items+=("normal:${src_module_name}:${src_cmd}")
                fi
            elif ak_command_exists_official "$src_cmd" || ak_command_exists_complex "$src_cmd"; then
                skipped_items+=("normal:${src_module_name}:${src_cmd}")
            else
                dest_cmds+=("$src_cmd")
                dest_descs+=("$src_desc")
                dest_usages+=("$src_usage")
                dest_examples+=("$src_example")
                dest_genuines+=("$src_genuine")
                imported_items+=("normal:${src_module_name}:${src_cmd}")
            fi
        done < <(ak_sync_extract_normal_module_entries "$src_module_file")

        ak_sync_write_normal_module_from_arrays "$dest_module_file" "$src_module_name" "$src_category" dest_cmds dest_genuines dest_descs dest_usages dest_examples
        [[ -n "$dest_doc_file" ]] || dest_doc_file="${AK_CUSTOM_DOC_MODULE_DIR}/${prefix}_${src_module_name}.md"
        ak_sync_write_normal_doc_from_arrays "$dest_doc_file" "$src_module_name" dest_cmds dest_genuines dest_descs dest_usages dest_examples
    else
        next_num=$(ak_get_next_custom_module_number)
        printf -v next_num '%02d' "$next_num"
        dest_module_file="${AK_CUSTOM_MODULE_DIR}/${next_num}_${src_module_name}.sh"
        dest_doc_file="${AK_CUSTOM_DOC_MODULE_DIR}/${next_num}_${src_module_name}.md"
        cp "$src_module_file" "$dest_module_file"
        chmod +x "$dest_module_file"
        src_doc_match=$(find "$source_custom_dir/docs/modules" -maxdepth 1 -type f -name "*_${src_module_name}.md" -o -name "${src_module_name}.md" 2>/dev/null | head -n1)
        if [[ -n "$src_doc_match" ]]; then
            cp "$src_doc_match" "$dest_doc_file"
        fi
        while IFS=$'\t' read -r src_cmd src_desc src_usage src_example src_genuine; do
            [[ -n "$src_cmd" ]] || continue
            imported_items+=("normal:${src_module_name}:${src_cmd}")
        done < <(ak_sync_extract_normal_module_entries "$src_module_file")
    fi
done < <(find "$source_custom_dir/modules" -maxdepth 1 -type f -name '*.sh' | sort)

while IFS= read -r src_cmd_file; do
    [[ -f "$src_cmd_file" ]] || continue
    src_complex_module=$(basename "$(dirname "$(dirname "$src_cmd_file")")")
    src_complex_cmd=$(basename "$src_cmd_file" .sh)
    src_complex_dir=$(dirname "$src_cmd_file")
    dest_complex_dir="${AK_COMPLEX_MODULE_ROOT}/${src_complex_module}/${src_complex_cmd}"
    dest_complex_doc_dir="${AK_COMPLEX_DOC_ROOT}/${src_complex_module}"
    replace_key="complex|${src_complex_module}|${src_complex_cmd}"

    if [[ -d "$dest_complex_dir" ]]; then
        if [[ -n "${replace_selected[$replace_key]:-}" ]]; then
            rm -rf "$dest_complex_dir"
            mkdir -p "${AK_COMPLEX_MODULE_ROOT}/${src_complex_module}"
            cp -R "$src_complex_dir" "$dest_complex_dir"
            mkdir -p "$dest_complex_doc_dir"
            src_complex_doc="${source_custom_dir}/docs/modules/complex/${src_complex_module}/${src_complex_cmd}.md"
            [[ -f "$src_complex_doc" ]] && cp "$src_complex_doc" "${dest_complex_doc_dir}/${src_complex_cmd}.md"
            replaced_items+=("complex:${src_complex_module}:${src_complex_cmd}")
        else
            skipped_items+=("complex:${src_complex_module}:${src_complex_cmd}")
        fi
    elif ak_command_exists_custom "$src_complex_cmd" || ak_command_exists_official "$src_complex_cmd"; then
        skipped_items+=("complex:${src_complex_module}:${src_complex_cmd}")
    else
        mkdir -p "${AK_COMPLEX_MODULE_ROOT}/${src_complex_module}" "$dest_complex_doc_dir"
        cp -R "$src_complex_dir" "$dest_complex_dir"
        src_complex_doc="${source_custom_dir}/docs/modules/complex/${src_complex_module}/${src_complex_cmd}.md"
        [[ -f "$src_complex_doc" ]] && cp "$src_complex_doc" "${dest_complex_doc_dir}/${src_complex_cmd}.md"
        imported_items+=("complex:${src_complex_module}:${src_complex_cmd}")
    fi
done < <(find "$source_custom_dir/modules/complex" -mindepth 2 -maxdepth 2 -type f -name '*.sh' 2>/dev/null | sort)

ak_write_custom_index
source "${AK_ROOT}/core/init.sh" >/dev/null 2>&1 || true

imported_json=$(printf '%s\n' "${imported_items[@]}" | jq -R . | jq -s .)
replaced_json=$(printf '%s\n' "${replaced_items[@]}" | jq -R . | jq -s .)
skipped_json=$(printf '%s\n' "${skipped_items[@]}" | jq -R . | jq -s .)
ak_sync_record_result "$package_name" "$repo_ref" "$imported_json" "$replaced_json" "$skipped_json"

print_color green "✔ Sync completed for package: $package_name"
echo "Imported: ${#imported_items[@]}"
echo "Replaced: ${#replaced_items[@]}"
echo "Skipped:  ${#skipped_items[@]}"