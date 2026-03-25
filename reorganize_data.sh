#!/usr/bin/env bash
#
# reorganize_data.sh — One-time migration: organize flat files into per-video subdirectories.
#
# Before: data/channel/VIDEOBASE.ext
# After:  data/channel/VIDEOBASE/VIDEOBASE.ext
#
# Uses mv + git add (git detects renames automatically with minimal storage overhead).
# Safe to run repeatedly — already-organized files are skipped.
#
# Usage:
#   ./reorganize_data.sh              # perform migration
#   ./reorganize_data.sh --dry-run    # preview what would be moved

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

echo "🔄 Reorganizing data into per-video subdirectories..."
echo ""

MOVE_COUNT=0
SKIP_COUNT=0

for channel_dir in "$DATA_DIR"/*/; do
    [ -d "$channel_dir" ] || continue
    channel=$(basename "$channel_dir")
    channel_moves=0

    # Process all items directly under channel/ (depth 1 only).
    # Glob is expanded once, so newly created video_base/ dirs won't be re-iterated.
    for item in "$channel_dir"*; do
        [ -e "$item" ] || continue
        name=$(basename "$item")

        # Skip hidden files (.DS_Store etc.)
        [[ "$name" == .* ]] && continue

        # Extract video base (pure bash — no subprocesses for speed)
        temp="${name%_whisper_prompt.*}"
        video_base="${temp%%.*}"

        # Skip if this IS the video_base directory (already organized from a previous run)
        if [ -d "$item" ] && [ "$name" = "$video_base" ]; then
            SKIP_COUNT=$((SKIP_COUNT + 1))
            continue
        fi

        target_dir="$channel_dir$video_base"

        if [ "$DRY_RUN" = true ]; then
            echo "   $channel/$name → $channel/$video_base/$name"
        else
            mkdir -p "$target_dir"
            mv "$item" "$target_dir/"
        fi

        channel_moves=$((channel_moves + 1))
        MOVE_COUNT=$((MOVE_COUNT + 1))
    done

    [ $channel_moves -gt 0 ] && echo "📂 $channel: moved $channel_moves items"
done

echo ""
if [ "$DRY_RUN" = true ]; then
    echo "🔍 Dry run: $MOVE_COUNT items would be moved ($SKIP_COUNT already organized)"
else
    echo "✅ Moved $MOVE_COUNT items ($SKIP_COUNT already organized)"
    echo ""
    echo "📝 Staging changes in git..."
    cd "$SCRIPT_DIR"
    git add -A data/
    echo "   Done. Review with 'git diff --cached --stat | tail' and commit when ready."
fi
