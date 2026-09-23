#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  trigger-builds.sh - Dispatch builds for what check-updates.sh found    ║
# ║                                                                         ║
# ║  Compares versions.json before and after a check and dispatches the     ║
# ║  Build Portable R workflow only for the architectures that changed, so  ║
# ║  published files for the other architecture are left untouched.         ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
#
# Usage: bash trigger-builds.sh versions-before.json versions.json
#        DRY_RUN=1 bash trigger-builds.sh ...   # print the plan only
set -euo pipefail

BEFORE="$1"
AFTER="$2"

# One line per build needed: "<version> <x64|aarch64> <new|refresh>"
PLAN=""
plan() { PLAN="${PLAN}$1 $2 $3"$'\n'; }

# ── New R versions ───────────────────────────────────────────────────────────
# ARM64 installers usually appear weeks after CRAN's x64 release (or, rarely,
# before it), so each architecture is built when it first shows up.

for arch in x64 aarch64; do
    for v in $(jq -r --arg a "$arch" --slurpfile b "$BEFORE" '.r[$a] - $b[0].r[$a] | .[]' "$AFTER"); do
        plan "$v" "$arch" new
    done
done

# ── Updated Rtools installers ────────────────────────────────────────────────
# A new Rtools build refreshes only the -full variant of the latest R version
# in each series that uses it (e.g. Rtools45 serves both 4.5.x and 4.6.x);
# the published R-only zips are left as they are. Older R versions keep
# their existing -full archives since they still work.

for RT in $(jq -r '.rtools | keys[] | select(. != "r_series")' "$AFTER"); do
    for arch in x64 aarch64; do
        was=$(jq -r --arg rt "$RT" --arg a "$arch" '.rtools[$rt][$a].file // empty' "$BEFORE")
        now=$(jq -r --arg rt "$RT" --arg a "$arch" '.rtools[$rt][$a].file // empty' "$AFTER")
        [ -n "$now" ] && [ "$was" != "$now" ] || continue
        echo "Rtools${RT} ${arch}: ${was:-none} -> $now"
        for series in $(jq -r --arg rt "$RT" '.rtools.r_series | to_entries[] | select(.value == $rt) | .key' "$AFTER"); do
            latest=$(jq -r --arg a "$arch" --arg s "$series" \
                '[.r[$a][] | select(startswith($s + "."))] | max_by(split(".") | map(tonumber)) // empty' "$AFTER")
            if [ -n "$latest" ]; then plan "$latest" "$arch" refresh; fi
        done
    done
done

# ── Newly mapped R series ────────────────────────────────────────────────────
# A series that had no Rtools mapping was built without Rtools; once
# check-updates.sh maps it, build its missing -full variant. (A mapping added
# by hand is committed before the next check, so it is not seen as new here;
# check-updates.sh's notice gives the build command to run for that case.)

for series in $(jq -r --slurpfile b "$BEFORE" '.rtools.r_series | keys - ($b[0].rtools.r_series | keys) | .[]' "$AFTER"); do
    for arch in x64 aarch64; do
        latest=$(jq -r --arg a "$arch" --arg s "$series" \
            '[.r[$a][] | select(startswith($s + "."))] | max_by(split(".") | map(tonumber)) // empty' "$AFTER")
        if [ -n "$latest" ]; then plan "$latest" "$arch" refresh; fi
    done
done

# ── Dispatch ─────────────────────────────────────────────────────────────────
# One build per version and architecture, so a failure on one architecture
# does not hold back the other (the release notes merge both). A new version
# gets the full build even if its Rtools also changed.

DISPATCHES=$(printf '%s' "$PLAN" | awk 'NF { k = $1 " " $2; if ($3 == "new" || !(k in kind)) kind[k] = $3 }
    END { for (k in kind) print k, kind[k] }' | sort -V)

if [ -z "$DISPATCHES" ]; then
    echo "Nothing to build"
    exit 0
fi

FAILED=0
while read -r v arch kind; do
    # Bundle Rtools only when versions.json maps this R series to an Rtools
    # with an installer for this architecture
    rt_file=$(jq -r --arg s "${v%.*}" --arg a "$arch" \
        '(.rtools.r_series[$s] // empty) as $rt | .rtools[$rt][$a].file // empty' "$AFTER")
    full_only=false
    if [ -n "$rt_file" ]; then
        rtools=true
    elif [ "$kind" = "refresh" ]; then
        # Nothing to refresh: there is no -full variant for this architecture
        echo "No $arch Rtools for R ${v%.*}; not refreshing R $v ($arch)"
        continue
    else
        # A new series waiting for manual setup still gets its R-only build
        rtools=false
        echo "::warning::No $arch Rtools mapped for R ${v%.*} in versions.json; building R $v without Rtools"
    fi

    # An Rtools refresh rebuilds only the -full variant when the R-only zip is
    # already published (a missing release or zip means build both, e.g.
    # after a failed build). Any other gh error skips the dispatch rather
    # than risk replacing a published zip.
    if [ "$kind" = "refresh" ]; then
        state=""
        for attempt in 1 2 3; do
            if ASSETS=$(gh release view "v$v" ${GITHUB_REPOSITORY:+--repo "$GITHUB_REPOSITORY"} \
                --json assets --jq '.assets[].name' 2>&1); then
                state=listed
                break
            elif [ "$ASSETS" = "release not found" ]; then
                state=missing
                break
            fi
            [ "$attempt" -lt 3 ] && sleep $((attempt * 20))
        done
        if [ -z "$state" ]; then
            echo "::error::Could not check the published assets of v$v ($ASSETS). Run it by hand: gh workflow run \"Build Portable R for Windows\" -f r_version=$v -f arch=$arch -f include_rtools=true -f full_only=true"
            FAILED=1
            continue
        fi
        if [ "$state" = listed ] && grep -qx "portable-r-$v-win-$arch.zip" <<< "$ASSETS"; then
            full_only=true
        else
            echo "R $v ($arch) has no published R-only zip; building both variants"
        fi
    fi

    echo "Triggering build for R $v ($arch, include_rtools=$rtools, full_only=$full_only)..."
    [ -n "${DRY_RUN:-}" ] && continue
    args=(-f r_version="$v" -f arch="$arch" -f include_rtools="$rtools" -f full_only="$full_only")
    ok=false
    for attempt in 1 2 3; do
        if gh workflow run "Build Portable R for Windows" "${args[@]}"; then
            ok=true
            break
        fi
        [ "$attempt" -lt 3 ] || break
        echo "Dispatch failed, retrying in $((attempt * 20))s..."
        sleep $((attempt * 20))
    done
    if [ "$ok" != true ]; then
        echo "::error::Failed to trigger the build for R $v ($arch). Run it by hand: gh workflow run \"Build Portable R for Windows\" ${args[*]}"
        FAILED=1
    fi
    sleep 5
done <<< "$DISPATCHES"

exit $FAILED
