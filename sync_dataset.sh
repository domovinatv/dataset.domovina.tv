#!/usr/bin/env bash
#
# sync_dataset.sh — Sync text-only files from the fetch output to this dataset repo.
#
# Copies only text/metadata files (.description, .srt, .diarized.srt, .txt, .json, .vtt)
# and excludes all binary/media files (.wav, .mp3, .mp4, .webm, .mkv, .png, .webp, .jpg, .m4a, .part)
# as well as macOS resource fork (._*) files.
#
# Usage:
#   ./sync_dataset.sh                          # sync only (no commits)
#   ./sync_dataset.sh --commit                 # sync + commit each video separately
#   ./sync_dataset.sh --commit --dry-run       # show what would be committed
#
# Safe to run repeatedly — rsync only copies new or changed files.

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
    "*.txt"
    "*.json"
    "*.vtt"
)

# --- Validation ---
if [ ! -d "$SOURCE" ]; then
    echo "❌ Source directory not found: $SOURCE"
    echo "   Make sure the external drive is mounted."
    exit 1
fi

# --- Build rsync include/exclude rules ---
# Strategy: exclude ._* first, include directories, include whitelisted extensions, exclude everything else.
RSYNC_FILTERS=()

# Exclude macOS resource fork files FIRST (before any includes can match them)
RSYNC_FILTERS+=(--exclude='._*')

# Include all directories so rsync can recurse
RSYNC_FILTERS+=(--include='*/')

# Include each whitelisted text extension
for ext in "${INCLUDE_EXTENSIONS[@]}"; do
    RSYNC_FILTERS+=(--include="$ext")
done

# Exclude everything else
RSYNC_FILTERS+=(--exclude='*')

# --- Sync ---
echo "📂 Source:      $SOURCE"
echo "📁 Destination: $DEST"
echo ""
echo "🔄 Syncing text files..."
echo ""

mkdir -p "$DEST"

rsync -av --prune-empty-dirs \
    "${RSYNC_FILTERS[@]}" \
    "$SOURCE/" \
    "$DEST/"

# --- Summary ---
echo ""
echo "✅ Sync complete!"
echo ""

# Count files by extension
echo "📊 Dataset summary:"
find "$DEST" -type f -not -name '._*' | sed 's/.*\.//' | sort | uniq -c | sort -rn | while read count ext; do
    printf "   %5d  .%s\n" "$count" "$ext"
done

TOTAL=$(find "$DEST" -type f -not -name '._*' | wc -l | tr -d ' ')
DIRS=$(find "$DEST" -type d | wc -l | tr -d ' ')
echo ""
echo "   Total: $TOTAL files across $DIRS directories"

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

# Extract unique video base names from changed files.
# Pattern: {show}/{date}_{title}_yt_{videoId}  (everything before first . or _whisper_prompt)
# We extract: show/date_title_yt_videoId as the grouping key
declare -A VIDEO_GROUPS

while IFS= read -r file; do
    # Get the basename without extensions
    basename=$(basename "$file")
    # Strip all extensions (handles .wav.srt, .wav.diarized.srt, .info.json, etc.)
    # Also handle _whisper_prompt.txt suffix
    video_base=$(echo "$basename" | sed -E 's/_whisper_prompt\..+$//' | sed -E 's/\..+$//')

    # Get the show directory (first path component under data/)
    show_dir=$(echo "$file" | sed -E 's|^data/([^/]+)/.*|\1|')

    # Group key: show/video_base
    group_key="${show_dir}/${video_base}"

    # Append file to this group
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
    video_title=$(echo "$video_base" | sed -E 's/^[0-9]{8}_//' | sed -E 's/_yt_[^_]+$//' | tr '_' ' ')

    # Extract YouTube ID
    yt_id=$(echo "$video_base" | grep -oE 'yt_[A-Za-z0-9_-]+$' | sed 's/^yt_//')

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
