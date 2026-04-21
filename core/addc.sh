#!/usr/bin/env bash

# core/addc.sh - shortcut wrapper for complex add flow

AK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash "${AK_ROOT}/core/add.sh" complex "$@"