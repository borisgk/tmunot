#!/bin/bash

echo "Cleaning up photo directories..."
rm -rf photos/*/originals/* 2>/dev/null || true
rm -rf photos/*/previews/* 2>/dev/null || true
rm -rf photos/*/thumbnails/* 2>/dev/null || true

echo "Cleaning up database..."
sqlite3 photos.db "DELETE FROM photo_exif; DELETE FROM photos;"

echo "Cleanup complete."
