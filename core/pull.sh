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
        *) echo "$2" ;;
    esac
}

repo_input="${1:-}"
[[ -n "$repo_input" ]] || {
    print_color red "Usage: ak pull <username/repo-name|full-github-url>"
    exit 1
}

ak_sync_require_tool git || exit 1
ak_sync_require_tool jq || exit 1
ak_registry_bootstrap

parsed=$(ak_sync_parse_repo_input "$repo_input") || {
    print_color red "Invalid GitHub repo reference. Use username/repo or full GitHub URL."
    exit 1
}

repo_ref=$(printf '%s' "$parsed" | cut -f1)
repo_name=$(printf '%s' "$parsed" | cut -f2)
repo_url=$(printf '%s' "$parsed" | cut -f3)
package_dir=$(ak_sync_package_dir "$repo_name")
branch="main"

rm -rf "$package_dir"
mkdir -p "$package_dir"

git -C "$package_dir" init -q || exit 1
git -C "$package_dir" remote add origin "$repo_url"
git -C "$package_dir" sparse-checkout init --cone >/dev/null 2>&1 || true
git -C "$package_dir" sparse-checkout set custom >/dev/null 2>&1 || true

if ! git -C "$package_dir" pull --depth=1 origin main >/dev/null 2>&1; then
    branch="master"
    git -C "$package_dir" pull --depth=1 origin master >/dev/null 2>&1 || {
        print_color red "Unable to pull custom/ from repository."
        rm -rf "$package_dir"
        exit 1
    }
fi

package_custom_dir=$(ak_sync_package_custom_dir "$repo_name")
if ! ak_sync_validate_package_dir "$package_custom_dir"; then
    print_color red "Pulled repository does not contain a valid custom package structure."
    rm -rf "$package_dir"
    exit 1
fi

ak_sync_upsert_package_state "$repo_name" "$repo_ref" "$repo_url" "$branch" "$package_dir" || exit 1

print_color green "✔ Package pulled successfully"
echo "- Repo:   $repo_ref"
echo "- Branch: $branch"
echo "- Saved:  $package_custom_dir"
echo "Run 'ak sync' to import commands into your active custom workspace."