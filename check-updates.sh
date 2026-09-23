#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  check-updates.sh - Detect new R and Rtools releases                    ║
# ║                                                                         ║
# ║  Scrapes CRAN and GitHub to find new R versions and Rtools builds,      ║
# ║  then updates versions.json. Designed to run in CI on a daily cron      ║
# ║  schedule.                                                              ║
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

# ── Helpers ──────────────────────────────────────────────────────────────────

fetch() {
    curl -fsSL --retry 3 --retry-delay 5 "$1" || {
        echo "Error: failed to fetch $1" >&2
        return 1
    }
}

# GitHub REST API; authenticated when a token is available (CI sets GH_TOKEN)
fetch_github_api() {
    local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    local auth=""
    [ -n "$token" ] && auth="Authorization: Bearer $token"
    curl -fsSL --retry 3 --retry-delay 5 \
        -H "Accept: application/vnd.github+json" ${auth:+-H "$auth"} "$1" || {
        echo "Error: failed to fetch $1" >&2
        return 1
    }
}

# An unreachable or unparseable upstream source is recorded and skipped so the
# other sources are still checked, LAST_CHECKED is still written, and the
# workflow can commit what it did find before reporting the failure.
FAILED=""
source_failed() {
    echo "  ERROR: $1" >&2
    [ "${GITHUB_ACTIONS:-}" = "true" ] && echo "::error title=check-updates::$1"
    FAILED="${FAILED}${FAILED:+; }$1"
}

# Something that needs a maintainer's attention but did not fail (e.g. a new
# Rtools major): reported as a warning and in LAST_CHECKED
NOTICES=""
notice() {
    echo "  NOTICE: $1"
    [ "${GITHUB_ACTIONS:-}" = "true" ] && echo "::warning title=check-updates::$1"
    NOTICES="${NOTICES}${NOTICES:+; }$1"
}

# Lines of $1 that are not lines of $2 (no sort order needed, unlike comm)
missing_from() {
    printf '%s\n' "$1" | grep -vxF -f <(printf '%s\n' "$2") | grep -v '^$' || true
}

update_versions() {
    local tmp
    tmp=$(mktemp)
    jq "$@" "$VERSIONS_FILE" > "$tmp"
    mv "$tmp" "$VERSIONS_FILE"
}

SORT_VERSIONS='map(split(".") | map(tonumber)) | sort | map(map(tostring) | join("."))'

# Use grep -oE (POSIX extended) instead of grep -oP (Perl, not on macOS)
# Extract version-like patterns and filter with sed/awk as needed

# ── Check R x64 versions ────────────────────────────────────────────────────

echo "-- R for Windows (x64) --"

NEW_X64=""
if ! BASE_PAGE=$(fetch "https://cloud.r-project.org/bin/windows/base/") \
    || ! OLD_PAGE=$(fetch "https://cloud.r-project.org/bin/windows/base/old/"); then
    source_failed "R x64: CRAN bin/windows/base unreachable"
else
    # Current version from the main download page (look for R-X.X.X-win.exe)
    CURRENT_R=$(echo "$BASE_PAGE" | grep -oE 'R-[0-9]+\.[0-9]+\.[0-9]+-win\.exe' \
        | head -1 | sed 's/^R-//; s/-win\.exe$//' || true)
    # All old versions from the archive
    OLD_VERSIONS=$(echo "$OLD_PAGE" | grep -oE 'href="[0-9]+\.[0-9]+\.[0-9]+' | sed 's/href="//' || true)

    if [ -z "$CURRENT_R" ] || [ -z "$OLD_VERSIONS" ]; then
        source_failed "R x64: no R versions found on CRAN bin/windows/base (page format changed?)"
    else
        echo "  Latest on CRAN: R $CURRENT_R"

        # Old versions + current, filtered to 4.3.0+ (our supported range)
        ALL_X64=$(printf '%s\n%s\n' "$OLD_VERSIONS" "$CURRENT_R" | sort -u \
            | awk -F. '$1>=4 && ($1>4 || $2>=3)')
        KNOWN_X64=$(jq -r '.r.x64[]' "$VERSIONS_FILE")

        NEW_X64=$(missing_from "$ALL_X64" "$KNOWN_X64")
        if [ -n "$NEW_X64" ]; then
            echo "  NEW: $NEW_X64"
            CHANGED=true
            for v in $NEW_X64; do
                update_versions --arg v "$v" ".r.x64 += [\$v] | .r.x64 |= ($SORT_VERSIONS)"
                echo "  Added R $v (x64)"
            done
        else
            echo "  Up to date"
        fi
    fi
fi

# ── Check R aarch64 versions ────────────────────────────────────────────────

# R 4.4.0-4.5.3 are Tomáš Kalibera's builds, a closed set pinned in
# versions.json (r.aarch64_legacy_sha256). Their original home,
# r-project.org/nosvn/winutf8/aarch64 (R-4-signed/, and R-4/ for the
# unsigned 4.5.3), has been offline since August 2026. R 4.6.0+ comes from
# the community r-devel/windows-arm64 project, which publishes one GitHub
# release per R version; each new installer's sha256 digest is recorded in
# r.aarch64_sha256.

echo ""
echo "-- R for Windows (aarch64) --"

NEW_AARCH64=""
AARCH64_RELEASES_API="https://api.github.com/repos/r-devel/windows-arm64/releases?per_page=100"
if ! AARCH64_RELEASES=$(fetch_github_api "$AARCH64_RELEASES_API"); then
    source_failed "R aarch64: r-devel/windows-arm64 releases unreachable"
elif ! ALL_AARCH64=$(echo "$AARCH64_RELEASES" | jq -r '
        .[] | select((.draft or .prerelease) | not) | .tag_name as $t
        | select($t | test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))
        | select(($t | split(".") | map(tonumber)) >= [4, 6, 0])
        | select(any(.assets[]; .name == "R-\($t)-aarch64.exe")) | $t'); then
    source_failed "R aarch64: unexpected response from $AARCH64_RELEASES_API"
elif [ -z "$ALL_AARCH64" ]; then
    source_failed "R aarch64: no R releases with aarch64 installers at $AARCH64_RELEASES_API"
else
    echo "  Latest on r-devel/windows-arm64: R $(echo "$ALL_AARCH64" | sort -V | tail -1)"
    KNOWN_AARCH64=$(jq -r '.r.aarch64[]' "$VERSIONS_FILE")

    # Releases that look like new R versions but lack the expected tag or
    # installer name (upstream naming change, or assets still uploading)
    UNRECOGNISED=$(echo "$AARCH64_RELEASES" | jq -r --argjson known "$(jq -c '.r.aarch64' "$VERSIONS_FILE")" '
        .[] | select((.draft or .prerelease) | not) | .tag_name as $t
        | select($t | test("^v?[0-9]+\\.[0-9]+\\.[0-9]+$")) | ($t | ltrimstr("v")) as $v
        | select(($v | split(".") | map(tonumber)) >= [4, 6, 0])
        | select(($known | index($v)) == null)
        | select(($t != $v) or (any(.assets[]; .name == "R-\($v)-aarch64.exe") | not)) | $t' || true)
    for t in $UNRECOGNISED; do
        notice "r-devel/windows-arm64 release $t has no installer named R-${t#v}-aarch64.exe under tag ${t#v} (naming changed?)"
    done

    NEW_AARCH64=$(missing_from "$ALL_AARCH64" "$KNOWN_AARCH64")
    if [ -n "$NEW_AARCH64" ]; then
        echo "  NEW: $NEW_AARCH64"
        CHANGED=true
        for v in $NEW_AARCH64; do
            DIGEST=$(echo "$AARCH64_RELEASES" | jq -r --arg v "$v" '
                .[] | select(.tag_name == $v) | .assets[]
                | select(.name == "R-\($v)-aarch64.exe") | .digest // empty
                | select(startswith("sha256:")) | ltrimstr("sha256:")')
            update_versions --arg v "$v" --arg sha "$DIGEST" \
                ".r.aarch64 += [\$v] | .r.aarch64 |= ($SORT_VERSIONS)
                 | if \$sha != \"\" then .r.aarch64_sha256[\$v] = \$sha else . end"
            echo "  Added R $v (aarch64, sha256 ${DIGEST:-not published})"
        done
    else
        echo "  Up to date"
    fi
fi

# ── Check for new Rtools major versions ──────────────────────────────────────
# A new major (e.g. Rtools46) needs manual setup in versions.json, so it is
# reported as a notice rather than changing anything here. Checked before the
# r_series inference below so a new R series is not guessed onto an older
# Rtools while a newer one is waiting to be set up.

echo ""
echo "-- Checking for new Rtools major versions --"
RT_VERSIONS=$(jq -r '.rtools | keys[] | select(. != "r_series")' "$VERSIONS_FILE" | sort -n)
NEW_RT_MAJOR=""
RT_MAJORS_CHECKED=false
if ! RTOOLS_PAGE=$(fetch "https://cran.r-project.org/bin/windows/Rtools/"); then
    source_failed "Rtools majors: CRAN bin/windows/Rtools unreachable"
else
    AVAILABLE_RT_VERSIONS=$(echo "$RTOOLS_PAGE" | grep -oE 'rtools[0-9]+/' | sed 's/rtools//; s/\///' | sort -un || true)
    MAX_KNOWN=$(echo "$RT_VERSIONS" | tail -1)
    if [ -z "$AVAILABLE_RT_VERSIONS" ]; then
        source_failed "Rtools majors: no rtoolsNN/ directories listed on CRAN bin/windows/Rtools"
    else
        RT_MAJORS_CHECKED=true
        for rt in $AVAILABLE_RT_VERSIONS; do
            if [ "$rt" -gt "$MAX_KNOWN" ]; then
                echo "  NEW Rtools version detected: Rtools${rt}"
                notice "Rtools${rt} is on CRAN: add it to versions.json and update r_series"
                NEW_RT_MAJOR="$rt"
            fi
        done
        [ -z "$NEW_RT_MAJOR" ] && echo "  No new major Rtools versions"
    fi
fi

# ── Infer r_series mapping for unmapped R series ───────────────────────────
# When a new R series first appears (e.g., 4.6.x), default r_series to the
# highest known Rtools within the same R major. Right ~95% of the time per
# CRAN's loose convention (R 4.4 + 4.5 each got a new Rtools; R 4.6 reuses
# Rtools45). A series is left unmapped (and reported every run until it is
# set up, building without Rtools meanwhile) while a newer Rtools major is
# waiting or the Rtools majors could not be checked.

UNMAPPED_SERIES=$(jq -r '.rtools.r_series as $mapped | (.r.x64 + .r.aarch64)
    | map(split(".")[0:2] | join(".")) | unique | map(select($mapped[.] == null)) | .[]' "$VERSIONS_FILE")

if [ -n "$UNMAPPED_SERIES" ]; then
    echo ""
    echo "-- r_series mapping inference --"
    MAX_MAPPED=$(jq -r '.rtools.r_series | keys | max_by(split(".") | map(tonumber)) // empty' "$VERSIONS_FILE")
    for series in $UNMAPPED_SERIES; do
        # Its latest R version, for the build to run once it is mapped by hand
        latest=$(jq -r --arg s "$series" \
            '[(.r.x64 + .r.aarch64)[] | select(startswith($s + "."))] | max_by(split(".") | map(tonumber))' "$VERSIONS_FILE")
        by_hand="set r_series by hand, then build its -full variant: gh workflow run \"Build Portable R for Windows\" -f r_version=$latest -f arch=<x64|aarch64> -f include_rtools=true -f full_only=true"

        exact="${series/./}"  # 4.2 -> Rtools42, if versions.json has it
        if jq -e --arg rt "$exact" '.rtools[$rt]' "$VERSIONS_FILE" >/dev/null; then
            fallback="$exact"
        elif [ -n "$NEW_RT_MAJOR" ]; then
            notice "R $series: not mapped to an Rtools while Rtools${NEW_RT_MAJOR} awaits setup (builds without Rtools until then); $by_hand"
            continue
        elif [ "$RT_MAJORS_CHECKED" != true ]; then
            notice "R $series: not mapped to an Rtools because the Rtools majors could not be checked; retried next run (builds without Rtools meanwhile)"
            continue
        elif [ -n "$MAX_MAPPED" ] && [ "$(printf '%s\n' "$series" "$MAX_MAPPED" | sort -V | tail -1)" != "$series" ]; then
            notice "R $series: older than the mapped series, so no Rtools is guessed; $by_hand"
            continue
        else
            r_major="${series%%.*}"
            fallback=$(jq -r '.rtools | keys[] | select(. != "r_series")' "$VERSIONS_FILE" \
                | awk -v m="$r_major" 'int($1/10) == m' | sort -n | tail -1)
            if [ -z "$fallback" ]; then
                notice "R $series: no Rtools in R ${r_major}.x to infer from (builds without Rtools until then); $by_hand"
                continue
            fi
        fi
        update_versions --arg s "$series" --arg rt "$fallback" '.rtools.r_series[$s] = $rt'
        CHANGED=true
        echo "  R $series -> Rtools$fallback (verify when next Rtools ships)"
    done
fi

# ── Check Rtools versions ───────────────────────────────────────────────────

echo ""
echo "-- Rtools --"

for RT in $RT_VERSIONS; do
    # x64 installer
    CRAN_URL="https://cran.r-project.org/bin/windows/Rtools/rtools${RT}/files/"
    KNOWN_X64=$(jq -r ".rtools.\"${RT}\".x64.file" "$VERSIONS_FILE")
    if ! PAGE=$(fetch "$CRAN_URL"); then
        source_failed "Rtools${RT} x64: $CRAN_URL unreachable"
    else
        LATEST_X64=$(echo "$PAGE" | grep -oE "rtools${RT}-[0-9]+-[0-9]+\.exe" | sort -V | tail -1 || true)
        if [ -z "$LATEST_X64" ]; then
            source_failed "Rtools${RT} x64: no installers listed at $CRAN_URL"
        elif [ "$LATEST_X64" != "$KNOWN_X64" ]; then
            echo "  Rtools${RT} x64: $KNOWN_X64 -> $LATEST_X64"
            CHANGED=true
            update_versions --arg rt "$RT" --arg f "$LATEST_X64" '.rtools[$rt].x64.file = $f'
        else
            echo "  Rtools${RT} x64: up to date ($KNOWN_X64)"
        fi
    fi

    # aarch64 installer
    KNOWN_AARCH64=$(jq -r ".rtools.\"${RT}\".aarch64.file // empty" "$VERSIONS_FILE")
    if [ -z "$KNOWN_AARCH64" ]; then
        echo "  Rtools${RT} aarch64: not available"
        continue
    fi
    # Installers pinned by sha256 are frozen mirrors with no directory listing
    # to scrape (Rtools43 aarch64: its original home on the now-offline
    # r-project.org/nosvn/winutf8 is gone; r-windows/rtools-chocolatey mirrors it)
    if jq -e ".rtools.\"${RT}\".aarch64.sha256" "$VERSIONS_FILE" >/dev/null; then
        echo "  Rtools${RT} aarch64: pinned ($KNOWN_AARCH64)"
        continue
    fi
    AARCH64_URL=$(jq -r ".rtools.\"${RT}\".aarch64.url" "$VERSIONS_FILE")
    if ! PAGE=$(fetch "$AARCH64_URL/"); then
        source_failed "Rtools${RT} aarch64: $AARCH64_URL/ unreachable"
        continue
    fi
    LATEST_AARCH64=$(echo "$PAGE" | grep -oE "rtools${RT}-aarch64-[0-9]+-[0-9]+\.exe" | sort -V | tail -1 || true)
    if [ -z "$LATEST_AARCH64" ]; then
        source_failed "Rtools${RT} aarch64: no installers listed at $AARCH64_URL/"
    elif [ "$LATEST_AARCH64" != "$KNOWN_AARCH64" ]; then
        echo "  Rtools${RT} aarch64: $KNOWN_AARCH64 -> $LATEST_AARCH64"
        CHANGED=true
        update_versions --arg rt "$RT" --arg f "$LATEST_AARCH64" '.rtools[$rt].aarch64.file = $f'
    else
        echo "  Rtools${RT} aarch64: up to date ($KNOWN_AARCH64)"
    fi
done

# ── Write LAST_CHECKED ───────────────────────────────────────────────────────

echo ""
echo "-- Writing LAST_CHECKED --"

{
    date -u +"%Y-%m-%dT%H:%M:%SZ"
    if [ -n "$FAILED" ]; then
        echo "Status: incomplete ($FAILED)"
    else
        echo "Status: ok"
    fi
    [ -n "$NOTICES" ] && echo "Notice: $NOTICES"

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
    for RT in $RT_VERSIONS; do
        X64_FILE=$(jq -r ".rtools.\"${RT}\".x64.file" "$VERSIONS_FILE")
        ARM_FILE=$(jq -r ".rtools.\"${RT}\".aarch64.file // \"n/a\"" "$VERSIONS_FILE")
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

# Unreachable sources are reported by the workflow after it has committed
# and triggered builds for everything else, so this script still exits 0.
echo "failed=$FAILED" >> "${GITHUB_OUTPUT:-/dev/null}"
if [ -n "$FAILED" ]; then
    echo "==> Incomplete: $FAILED" >&2
fi
