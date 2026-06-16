#!/usr/bin/env bash
#
set -euo pipefail

if [[ -z "${CONDA_PREFIX:-}" ]]; then
    echo "error: CONDA_PREFIX is not set. Activate radioconda env first," >&2
    echo "       e.g.  conda activate radioconda" >&2
    exit 1
fi

PFX="$CONDA_PREFIX"
BUILD_TYPE="${BUILD_TYPE:-Release}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PKG_CONFIG_PATH="$PFX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

if [[ "${1:-}" == "clean" ]]; then
    rm -rf "$REPO/librx888/build" "$REPO/build"
fi

build_project() {
    local name="$1" src="$2"
    cmake -S "$src" -B "$src/build" \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DCMAKE_INSTALL_PREFIX="$PFX" \
        -DCMAKE_PREFIX_PATH="$PFX"
    cmake --build "$src/build"
    cmake --install "$src/build"
}

build_project "librx888"   "$REPO/librx888"
build_project "SoapyRX888" "$REPO"
