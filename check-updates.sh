#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  check-updates.sh - Detect new R and Rtools releases                    ║
# ║                                                                         ║
# ║  Scrapes CRAN and r-project.org to find new R versions and Rtools       ║
# ║  builds, then updates versions.json. Designed to run in CI on a         ║
# ║  daily cron schedule.                                                   ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
set -euo pipefail

VERSIONS_FILE="versions.json"
CHANGED=false

# Require jq
if ! command -v jq &>/dev/null; then
    echo "Error: jq is required" >&2
    exit 1
fi

if [ ! -f "$VERSIONS_FILE" ]; then
    echo "Error: $VERSIONS_FILE not found" >&2
    exit 1
fi

echo "==> Checking for new R and Rtools releases"
echo ""

# ── Helper ───────────────────────────────────────────────────────────────────

fetch() {
    curl -fsSL --retry 3 --retry-delay 5 "$1" 2>/dev/null
}

# Use grep -oE (POSIX extended) instead of grep -oP (Perl, not on macOS)
# Extract version-like patterns and filter with sed/awk as needed

# ── Check R x64 versions ────────────────────────────────────────────────────

echo "-- R for Windows (x64) --"

# Current version from the main download page (look for R-X.X.X-win.exe)
CURRENT_R=$(fetch "https://cloud.r-project.org/bin/windows/base/" \
    | grep -oE 'R-[0-9]+\.[0-9]+\.[0-9]+-win\.exe' | head -1 | sed 's/^R-//; s/-win\.exe$//')
echo "  Latest on CRAN: R $CURRENT_R"

# All old versions from the archive
OLD_VERSIONS=$(fetch "https://cloud.r-project.org/bin/windows/base/old/" \
    | grep -oE 'href="[0-9]+\.[0-9]+\.[0-9]+' | sed 's/href="//' | sort -V)

# Combine: old versions + current
ALL_X64=$(printf '%s\n%s\n' "$OLD_VERSIONS" "$CURRENT_R" | sort -V | uniq)

# Filter to 4.3.0+ (our supported range)
ALL_X64=$(echo "$ALL_X64" | awk -F. '$1>=4 && ($1>4 || $2>=3)')

# Current known versions
KNOWN_X64=$(jq -r '.r.x64[]' "$VERSIONS_FILE" | sort -V)

# Find new versions
NEW_X64=$(comm -23 <(echo "$ALL_X64") <(echo "$KNOWN_X64"))
if [ -n "$NEW_X64" ]; then
    echo "  NEW: $NEW_X64"
    CHANGED=true
    for v in $NEW_X64; do
        VERSIONS_FILE_TMP=$(mktemp)
        jq --arg v "$v" '.r.x64 += [$v] | .r.x64 |= (map(split(".") | map(tonumber)) | sort | map(map(tostring) | join(".")))' \
            "$VERSIONS_FILE" > "$VERSIONS_FILE_TMP"
        mv "$VERSIONS_FILE_TMP" "$VERSIONS_FILE"
        echo "  Added R $v (x64)"
    done
else
    echo "  Up to date"
fi

# ── Check R aarch64 versions ────────────────────────────────────────────────

echo ""
echo "-- R for Windows (aarch64) --"

ALL_AARCH64=$(fetch "https://www.r-project.org/nosvn/winutf8/aarch64/R-4-signed/" \
    | grep -oE 'R-[0-9]+\.[0-9]+\.[0-9]+-aarch64\.exe' | sed 's/^R-//; s/-aarch64\.exe$//' | sort -V | uniq)

KNOWN_AARCH64=$(jq -r '.r.aarch64[]' "$VERSIONS_FILE" | sort -V)

NEW_AARCH64=$(comm -23 <(echo "$ALL_AARCH64") <(echo "$KNOWN_AARCH64"))
if [ -n "$NEW_AARCH64" ]; then
    echo "  NEW: $NEW_AARCH64"
    CHANGED=true
    for v in $NEW_AARCH64; do
        VERSIONS_FILE_TMP=$(mktemp)
        jq --arg v "$v" '.r.aarch64 += [$v] | .r.aarch64 |= (map(split(".") | map(tonumber)) | sort | map(map(tostring) | join(".")))' \
            "$VERSIONS_FILE" > "$VERSIONS_FILE_TMP"
        mv "$VERSIONS_FILE_TMP" "$VERSIONS_FILE"
        echo "  Added R $v (aarch64)"
    done
else
    echo "  Up to date"
fi

# ── Infer r_series mapping for newly-added R series ─────────────────────────
# When a new R series first appears (e.g., 4.6.x), default r_series to the
# highest known Rtools within the same R major. Right ~95% of the time per
# CRAN's loose convention (R 4.4 + 4.5 each got a new Rtools; R 4.6 reuses
# Rtools45). When R Core does ship a new Rtools major, the existing
# "new Rtools major" detector below flags it for manual review.

if [ -n "$NEW_X64$NEW_AARCH64" ]; then
    echo ""
    echo "-- r_series mapping inference --"
    for v in $NEW_X64 $NEW_AARCH64; do
        series="${v%.*}"
        if jq -e --arg s "$series" '.rtools.r_series[$s]' "$VERSIONS_FILE" >/dev/null; then
            continue
        fi
        r_major="${series%%.*}"
        fallback=$(jq -r '.rtools | keys[] | select(. != "r_series")' "$VERSIONS_FILE" \
            | awk -v m="$r_major" 'int($1/10) == m' | sort -n | tail -1)
        if [ -z "$fallback" ]; then
            echo "  R $series: no Rtools in R ${r_major}.x to infer from -- manual setup required"
            continue
        fi
        VERSIONS_FILE_TMP=$(mktemp)
        jq --arg s "$series" --arg rt "$fallback" '.rtools.r_series[$s] = $rt' \
            "$VERSIONS_FILE" > "$VERSIONS_FILE_TMP"
        mv "$VERSIONS_FILE_TMP" "$VERSIONS_FILE"
        echo "  R $series -> Rtools$fallback (verify when next Rtools ships)"
    done
fi

# ── Check Rtools versions ───────────────────────────────────────────────────

echo ""
echo "-- Rtools --"

for RT in 43 44 45; do
    # x64 installer
    CRAN_URL="https://cran.r-project.org/bin/windows/Rtools/rtools${RT}/files/"
    LATEST_X64=$(fetch "$CRAN_URL" \
        | grep -oE "rtools${RT}-[0-9]+-[0-9]+\.exe" | sort -V | tail -1)

    KNOWN_X64=$(jq -r ".rtools.\"${RT}\".x64.file" "$VERSIONS_FILE")

    if [ -n "$LATEST_X64" ] && [ "$LATEST_X64" != "$KNOWN_X64" ]; then
        echo "  Rtools${RT} x64: $KNOWN_X64 -> $LATEST_X64"
        CHANGED=true
        VERSIONS_FILE_TMP=$(mktemp)
        jq --arg rt "$RT" --arg f "$LATEST_X64" \
            '.rtools[$rt].x64.file = $f' "$VERSIONS_FILE" > "$VERSIONS_FILE_TMP"
        mv "$VERSIONS_FILE_TMP" "$VERSIONS_FILE"
    else
        echo "  Rtools${RT} x64: up to date ($KNOWN_X64)"
    fi

    # aarch64 installer
    KNOWN_AARCH64=$(jq -r ".rtools.\"${RT}\".aarch64.file" "$VERSIONS_FILE")
    AARCH64_URL=$(jq -r ".rtools.\"${RT}\".aarch64.url" "$VERSIONS_FILE")

    LATEST_AARCH64=$(fetch "$AARCH64_URL/" \
        | grep -oE "rtools${RT}-aarch64-[0-9]+-[0-9]+\.exe" | sort -V | tail -1)

    if [ -n "$LATEST_AARCH64" ] && [ "$LATEST_AARCH64" != "$KNOWN_AARCH64" ]; then
        echo "  Rtools${RT} aarch64: $KNOWN_AARCH64 -> $LATEST_AARCH64"
        CHANGED=true
        VERSIONS_FILE_TMP=$(mktemp)
        jq --arg rt "$RT" --arg f "$LATEST_AARCH64" \
            '.rtools[$rt].aarch64.file = $f' "$VERSIONS_FILE" > "$VERSIONS_FILE_TMP"
        mv "$VERSIONS_FILE_TMP" "$VERSIONS_FILE"
    else
        echo "  Rtools${RT} aarch64: up to date ($KNOWN_AARCH64)"
    fi
done

# ── Check for new Rtools major versions ──────────────────────────────────────

echo ""
echo "-- Checking for new Rtools major versions --"
RTOOLS_PAGE=$(fetch "https://cran.r-project.org/bin/windows/Rtools/")
KNOWN_RT_VERSIONS=$(jq -r '.rtools | keys[] | select(. != "r_series")' "$VERSIONS_FILE" | sort)
AVAILABLE_RT_VERSIONS=$(echo "$RTOOLS_PAGE" | grep -oE 'rtools[0-9]+/' | sed 's/rtools//; s/\///' | sort -u)

NEW_RT=$(comm -23 <(echo "$AVAILABLE_RT_VERSIONS") <(echo "$KNOWN_RT_VERSIONS"))
if [ -n "$NEW_RT" ]; then
    for rt in $NEW_RT; do
        MAX_KNOWN=$(echo "$KNOWN_RT_VERSIONS" | tail -1)
        if [ "$rt" -gt "$MAX_KNOWN" ]; then
            echo "  NEW Rtools version detected: Rtools${rt}"
            echo "  Manual setup required — add to versions.json and update r_series mapping"
            CHANGED=true
        fi
    done
else
    echo "  No new major Rtools versions"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

# ── Write LAST_CHECKED ───────────────────────────────────────────────────────

echo ""
echo "-- Writing LAST_CHECKED --"

{
    date -u +"%Y-%m-%dT%H:%M:%SZ"

    # Summarize R versions
    X64_COUNT=$(jq -r '.r.x64 | length' "$VERSIONS_FILE")
    X64_FIRST=$(jq -r '.r.x64[0]' "$VERSIONS_FILE")
    X64_LAST=$(jq -r '.r.x64[-1]' "$VERSIONS_FILE")
    echo "R x64: ${X64_FIRST}-${X64_LAST} (${X64_COUNT} versions)"

    ARM_COUNT=$(jq -r '.r.aarch64 | length' "$VERSIONS_FILE")
    ARM_FIRST=$(jq -r '.r.aarch64[0]' "$VERSIONS_FILE")
    ARM_LAST=$(jq -r '.r.aarch64[-1]' "$VERSIONS_FILE")
    echo "R aarch64: ${ARM_FIRST}-${ARM_LAST} (${ARM_COUNT} versions)"

    # Summarize Rtools
    for RT in 43 44 45; do
        X64_FILE=$(jq -r ".rtools.\"${RT}\".x64.file" "$VERSIONS_FILE")
        ARM_FILE=$(jq -r ".rtools.\"${RT}\".aarch64.file" "$VERSIONS_FILE")
        echo "Rtools${RT} x64: ${X64_FILE}"
        echo "Rtools${RT} aarch64: ${ARM_FILE}"
    done
} > LAST_CHECKED

echo "  $(head -1 LAST_CHECKED)"

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
if [ "$CHANGED" = true ]; then
    echo "==> versions.json updated"
    echo "changed=true" >> "${GITHUB_OUTPUT:-/dev/null}"
else
    echo "==> Everything up to date"
    echo "changed=false" >> "${GITHUB_OUTPUT:-/dev/null}"
fi
