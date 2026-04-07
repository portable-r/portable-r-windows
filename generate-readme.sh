#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  generate-readme.sh - Update README.md tables from GitHub releases      ║
# ║                                                                         ║
# ║  Queries the GitHub releases API to find published assets, then         ║
# ║  injects version tables between <!-- BEGIN/END RELEASES --> markers.    ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
set -euo pipefail

REPO="${REPO:-portable-r/portable-r-windows}"
README="README.md"

if ! command -v gh &>/dev/null; then
    echo "Error: gh CLI is required" >&2
    exit 1
fi

if [ ! -f "$README" ]; then
    echo "Error: $README not found" >&2
    exit 1
fi

echo "==> Querying releases from $REPO"

# ── Fetch all releases and their assets ──────────────────────────────────────

RELEASES_JSON=$(gh api "repos/${REPO}/releases" --paginate --jq '
  [.[] | {
    tag: .tag_name,
    assets: [.assets[] | {name: .name, size: .size}]
  }]
')

# ── Build R version table ────────────────────────────────────────────────────

DL="https://github.com/${REPO}/releases/download"

# Extract R versions from v* tags, sorted descending
R_VERSIONS=$(echo "$RELEASES_JSON" | jq -r '
  [.[].tag | select(startswith("v")) | ltrimstr("v")] | unique | sort_by(split(".") | map(tonumber)) | reverse | .[]
')

# Helper: find asset and format as "download (SIZE)" link
asset_link() {
    local tag="$1" pattern="$2" dl_url="$3"
    local match size_bytes size_mb
    match=$(echo "$RELEASES_JSON" | jq -r --arg tag "$tag" --arg pat "$pattern" '
      .[] | select(.tag == $tag) | .assets[] | select(.name | test($pat)) | "\(.name)\t\(.size)"
    ' | head -1)
    [ -z "$match" ] && return
    size_bytes=$(echo "$match" | cut -f2)
    size_mb=$(( size_bytes / 1048576 ))
    echo "[download](${dl_url}) (${size_mb} MB)"
}

generate_r_table() {
    echo "### R (with optional Rtools bundle)"
    echo ""
    echo "| R Version | x64 | x64 + Rtools | ARM64 | ARM64 + Rtools |"
    echo "|-----------|-----|-------------|-------|----------------|"

    for v in $R_VERSIONS; do
        x64=$(asset_link "v${v}" "portable-r-${v}-win-x64\\.zip$" "${DL}/v${v}/portable-r-${v}-win-x64.zip")
        x64_full=$(asset_link "v${v}" "portable-r-${v}-win-x64-full\\.(zip|7z)$" "")
        arm=$(asset_link "v${v}" "portable-r-${v}-win-aarch64\\.zip$" "${DL}/v${v}/portable-r-${v}-win-aarch64.zip")
        arm_full=$(asset_link "v${v}" "portable-r-${v}-win-aarch64-full\\.(zip|7z)$" "")

        # Resolve actual URL for full variants (could be .zip or .7z)
        if [ -n "$x64_full" ]; then
            fname=$(echo "$RELEASES_JSON" | jq -r --arg tag "v${v}" '.[] | select(.tag == $tag) | .assets[] | select(.name | test("portable-r-'"${v}"'-win-x64-full\\.(zip|7z)$")) | .name' | head -1)
            x64_full=$(asset_link "v${v}" "portable-r-${v}-win-x64-full\\.(zip|7z)$" "${DL}/v${v}/${fname}")
        fi
        if [ -n "$arm_full" ]; then
            fname=$(echo "$RELEASES_JSON" | jq -r --arg tag "v${v}" '.[] | select(.tag == $tag) | .assets[] | select(.name | test("portable-r-'"${v}"'-win-aarch64-full\\.(zip|7z)$")) | .name' | head -1)
            arm_full=$(asset_link "v${v}" "portable-r-${v}-win-aarch64-full\\.(zip|7z)$" "${DL}/v${v}/${fname}")
        fi

        echo "| ${v} | ${x64} | ${x64_full} | ${arm} | ${arm_full} |"
    done
}

# ── Build Rtools standalone table ────────────────────────────────────────────

RT_TAGS=$(echo "$RELEASES_JSON" | jq -r '
  [.[].tag | select(startswith("rtools"))] | unique | sort | reverse | .[]
')

SERIES_MAP='{"43":"4.3","44":"4.4","45":"4.5"}'

generate_rtools_table() {
    if [ -z "$RT_TAGS" ]; then
        return
    fi

    echo ""
    echo "### Standalone Rtools"
    echo ""
    echo "| Version | R Series | x64 | ARM64 |"
    echo "|---------|----------|-----|-------|"

    for tag in $RT_TAGS; do
        rt="${tag#rtools}"  # rtools45 -> 45
        series=$(echo "$SERIES_MAP" | jq -r --arg rt "$rt" '.[$rt] // "?"')

        x64=$(asset_link "$tag" "portable-rtools${rt}-win-x64\\.zip$" "${DL}/${tag}/portable-rtools${rt}-win-x64.zip")
        arm=$(asset_link "$tag" "portable-rtools${rt}-win-aarch64\\.zip$" "${DL}/${tag}/portable-rtools${rt}-win-aarch64.zip")

        echo "| Rtools${rt} | R ${series}.x | ${x64} | ${arm} |"
    done
}

# ── Inject into README ───────────────────────────────────────────────────────

if [ -z "$R_VERSIONS" ] && [ -z "$RT_TAGS" ]; then
    echo "No releases found — skipping README update"
    exit 0
fi

# Write table to temp file, then splice into README between markers
TABLE_FILE=$(mktemp)
generate_r_table > "$TABLE_FILE"
generate_rtools_table >> "$TABLE_FILE"

{
    # Print everything before and including BEGIN marker
    sed -n '1,/<!-- BEGIN RELEASES -->/p' "$README"
    echo ""
    cat "$TABLE_FILE"
    echo ""
    # Print everything from END marker onward
    sed -n '/<!-- END RELEASES -->/,$p' "$README"
} > "${README}.tmp"
mv "${README}.tmp" "$README"
rm -f "$TABLE_FILE"

COUNT=$(echo "$R_VERSIONS" | wc -w | tr -d ' ')
echo "==> Updated README with $COUNT R versions"
