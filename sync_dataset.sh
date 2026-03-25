#!/usr/bin/env bash
#
# sync_dataset.sh — Sync text-only files from the fetch output to this dataset repo.
#
# Copies only text/metadata files (.description, .srt, .diarized.srt, .txt, .json, .vtt)
# and excludes all binary/media files (.wav, .mp3, .mp4, .webm, .mkv, .png, .webp, .jpg, .m4a, .part)
# as well as macOS resource fork (._*) files.
#
# Files are organized into per-video subdirectories:
#   data/channel/YYYYMMDD_title_yt_VIDEOID/YYYYMMDD_title_yt_VIDEOID.ext
#
# Usage:
#   ./sync_dataset.sh                          # sync only (no commits)
#   ./sync_dataset.sh --commit                 # sync + commit each video separately
#   ./sync_dataset.sh --commit --dry-run       # show what would be committed
#
# Safe to run repeatedly — only copies new or changed files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Configuration ---
DEFAULT_SOURCE="/Volumes/DOMOVINA1TB/fetch_domovina_tv_output"
DEFAULT_DEST="$SCRIPT_DIR/data"

# --- Parse arguments ---
DO_COMMIT=false
DRY_RUN=false
SOURCE="$DEFAULT_SOURCE"
DEST="$DEFAULT_DEST"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit)  DO_COMMIT=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help|-h)
            echo "Usage: $0 [--commit] [--dry-run] [SOURCE] [DEST]"
            echo ""
            echo "Options:"
            echo "  --commit   Create a separate git commit for each YouTube video"
            echo "  --dry-run  Show what would be committed without actually committing"
            echo ""
            echo "Defaults:"
            echo "  SOURCE: $DEFAULT_SOURCE"
            echo "  DEST:   $DEFAULT_DEST"
            exit 0
            ;;
        *)
            if [ "$SOURCE" = "$DEFAULT_SOURCE" ]; then
                SOURCE="$1"
            else
                DEST="$1"
            fi
            shift
            ;;
    esac
done

# Text file extensions to include (whitelist approach)
INCLUDE_EXTENSIONS=(
    "*.description"
    "*.srt"
    "*.diarized.srt"
    "*.canary.srt"
    "*.canary.csv"
    "*.txt"
    "*.json"
    "*.jsonl"
    "*.vtt"
)

# --- Validation ---
if [ ! -d "$SOURCE" ]; then
    echo "❌ Source directory not found: $SOURCE"
    echo "   Make sure the external drive is mounted."
    exit 1
fi

# --- Build rsync include/exclude rules ---
RSYNC_FILTERS=()
RSYNC_FILTERS+=(--exclude='._*')
RSYNC_FILTERS+=(--include='*/')
for ext in "${INCLUDE_EXTENSIONS[@]}"; do
    RSYNC_FILTERS+=(--include="$ext")
done
RSYNC_FILTERS+=(--exclude='*')

# --- Sync ---
# Strategy: rsync bulk-syncs from source to a local staging cache (flat structure,
# matching the source layout). The staging cache persists between runs so rsync
# stays incremental — only new/changed files get transferred from the external drive.
# On first run, the cache is seeded from existing organized data via hardlinks
# (instant, no extra disk space). Only newly transferred files are then organized
# into per-video folders.

STAGING="$SCRIPT_DIR/.sync_staging"

echo "📂 Source:      $SOURCE"
echo "📁 Destination: $DEST"
echo ""
echo "🔄 Syncing text files..."

mkdir -p "$DEST" "$STAGING"

# Seed staging cache from existing organized data (one-time, uses hardlinks = no extra space)
if [ ! -f "$STAGING/.seeded" ] && [ -d "$DEST" ]; then
    echo "   Initializing sync cache (one-time)..."
    find "$DEST" -type f -not -name '._*' -not -name '.DS_Store' | while IFS= read -r f; do
        rel="${f#$DEST/}"           # channel/video_base/filename or channel/video_base/subdir/filename
        channel="${rel%%/*}"
        rest="${rel#*/}"            # video_base/filename or video_base/subdir/filename
        flat_rest="${rest#*/}"      # filename or subdir/filename (strip video_base/)
        target="$STAGING/$channel/$flat_rest"
        mkdir -p "$(dirname "$target")"
        ln -f "$f" "$target" 2>/dev/null || true
    done
    touch "$STAGING/.seeded"
    echo "   Cache ready."
fi

# Step 1: Fast bulk rsync from source → staging cache
# --out-format='%n' outputs only the relative paths of actually transferred files
echo "   rsync: scanning source..."
TRANSFERRED=$(rsync -a --prune-empty-dirs --out-format='%n' \
    "${RSYNC_FILTERS[@]}" "$SOURCE/" "$STAGING/")

# Step 2: Organize only newly transferred files into per-video folders
SYNC_COUNT=0

while IFS= read -r rel_path; do
    [ -z "$rel_path" ] && continue
    src="$STAGING/$rel_path"
    [ -f "$src" ] || continue  # skip directory entries

    # Split: channel/rest (flat file) or channel/subdir/file (nested)
    channel="${rel_path%%/*}"
    rest="${rel_path#*/}"

    if [[ "$rest" == */* ]]; then
        # File inside a subdirectory (e.g. _raw/): preserve subdir structure
        subdir="${rest%%/*}"
        filename="${rest#*/}"
        temp="${subdir%_whisper_prompt.*}"
        video_base="${temp%%.*}"
        dest_dir="$DEST/$channel/$video_base/$subdir"
    else
        # Flat file
        filename="$rest"
        temp="${filename%_whisper_prompt.*}"
        video_base="${temp%%.*}"
        dest_dir="$DEST/$channel/$video_base"
    fi

    mkdir -p "$dest_dir"
    ln -f "$src" "$dest_dir/$filename" 2>/dev/null || cp -p "$src" "$dest_dir/$filename"
    echo "   $channel/$video_base/$filename"
    SYNC_COUNT=$((SYNC_COUNT + 1))
done <<< "$TRANSFERRED"

# --- Summary ---
echo ""
echo "✅ Sync complete! ($SYNC_COUNT new/updated files)"
echo ""

# Count files by extension
echo "📊 Dataset summary:"
find "$DEST" -type f -not -name '._*' | sed 's/.*\.//' | sort | uniq -c | sort -rn | while read count ext; do
    printf "   %5d  .%s\n" "$count" "$ext"
done

TOTAL=$(find "$DEST" -type f -not -name '._*' | wc -l | tr -d ' ')
VIDEOS=$(find "$DEST" -mindepth 2 -maxdepth 2 -type d | wc -l | tr -d ' ')
CHANNELS=$(find "$DEST" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
echo ""
echo "   Total: $TOTAL files across $VIDEOS videos in $CHANNELS channels"

# --- Per-video git commits ---
if [ "$DO_COMMIT" = false ]; then
    echo ""
    echo "💡 Tip: use --commit to automatically create per-video git commits"
    exit 0
fi

echo ""
echo "📝 Creating per-video git commits..."
echo ""

cd "$SCRIPT_DIR"

# Get list of new/modified/untracked files in data/
# -uall ensures individual files inside untracked dirs are listed
CHANGED_FILES=$(git status --porcelain -uall "$DEST" 2>/dev/null | sed 's/^...//')

if [ -z "$CHANGED_FILES" ]; then
    echo "   No changes to commit."
    exit 0
fi

# Group changed files by video directory (data/channel/video_base/)
declare -A VIDEO_GROUPS

while IFS= read -r file; do
    # Extract channel/video_base from path: data/channel/video_base/...
    group_key=$(echo "$file" | awk -F'/' '{print $2"/"$3}')

    if [ -n "${VIDEO_GROUPS[$group_key]+x}" ]; then
        VIDEO_GROUPS[$group_key]="${VIDEO_GROUPS[$group_key]}"$'\n'"$file"
    else
        VIDEO_GROUPS[$group_key]="$file"
    fi
done <<< "$CHANGED_FILES"

COMMIT_COUNT=0
TOTAL_VIDEOS=${#VIDEO_GROUPS[@]}

echo "   Found $TOTAL_VIDEOS video(s) with changes"
echo ""

for group_key in $(echo "${!VIDEO_GROUPS[@]}" | tr ' ' '\n' | sort); do
    files="${VIDEO_GROUPS[$group_key]}"
    file_count=$(echo "$files" | wc -l | tr -d ' ')

    # Extract show name and video base for commit message
    show_dir=$(echo "$group_key" | cut -d'/' -f1)
    video_base=$(echo "$group_key" | cut -d'/' -f2-)

    # Make show name human-readable (replace _ with spaces)
    show_name=$(echo "$show_dir" | tr '_' ' ')

    # Extract date (first 8 chars: YYYYMMDD) and format it
    video_date=$(echo "$video_base" | grep -oE '^[0-9]{8}' || echo "")
    if [ -n "$video_date" ]; then
        formatted_date="${video_date:0:4}-${video_date:4:2}-${video_date:6:2}"
    else
        formatted_date="unknown-date"
    fi

    # Extract a human-readable title (between date_ and _yt_)
    video_title=$(echo "$video_base" | sed -E 's/^[0-9]{8}_//' | sed -E 's/_yt_[^/]+$//' | tr '_' ' ')

    # Extract YouTube ID
    yt_id=$(echo "$video_base" | grep -oE 'yt_[A-Za-z0-9_-]+$' | sed 's/^yt_//' || true)

    # Build commit message
    commit_msg="data(${show_dir}): ${formatted_date} ${video_title}"
    if [ -n "$yt_id" ]; then
        commit_msg="${commit_msg}

YouTube: https://youtube.com/watch?v=${yt_id}
Files: ${file_count}"
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "   [DRY RUN] Would commit $file_count file(s): $commit_msg"
    else
        # Stage files for this video
        echo "$files" | xargs git add

        # Commit
        git commit -m "$commit_msg" --quiet
        COMMIT_COUNT=$((COMMIT_COUNT + 1))

        printf "   [%d/%d] ✅ %s (%d files)\n" "$COMMIT_COUNT" "$TOTAL_VIDEOS" "${show_dir}/${formatted_date}" "$file_count"
    fi
done

echo ""
if [ "$DRY_RUN" = true ]; then
    echo "🔍 Dry run complete — $TOTAL_VIDEOS video(s) would be committed"
else
    echo "✅ Committed $COMMIT_COUNT video(s)"
fi
