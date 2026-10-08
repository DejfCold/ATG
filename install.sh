#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ATG_SOURCE_DIR=$script_dir
export ATG_SOURCE_DIR
exec bash "$script_dir/installer-runtime.sh"
