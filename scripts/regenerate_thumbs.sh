#!/bin/bash
set -euo pipefail

PREVIEWS_DIR="./photos/previews"
THUMBNAILS_DIR="./photos/thumbnails"
SIZE="400"

if [ ! -d "$PREVIEWS_DIR" ]; then
    echo "Previews directory $PREVIEWS_DIR does not exist!" >&2
    exit 1
fi

echo "Starting thumbnail regeneration (300px largest side)..."
count=0

# Recursively find all files in the previews directory, ignoring hidden files
while IFS= read -r preview_file; do
    # Get the relative path of the file starting from previews directory
    rel_path="${preview_file#$PREVIEWS_DIR/}"
    thumb_file="$THUMBNAILS_DIR/$rel_path"
    thumb_dir="$(dirname "$thumb_file")"
    
    # Ensure destination directory exists
    mkdir -p "$thumb_dir"
    
    # Generate the thumbnail (constraining width and height to $SIZE)
    vips thumbnail "$preview_file" "$thumb_file" $SIZE --height $SIZE
    
    count=$((count + 1))
    if [ $((count % 20)) -eq 0 ]; then
        echo "Processed $count files..."
    fi
done < <(find "$PREVIEWS_DIR" -type f -not -name ".*")

echo "Finished! Processed $count thumbnails."
