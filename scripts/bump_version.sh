#!/bin/bash
set -e

# Default to patch bump
BUMP_TYPE=${1:-patch}

ZON_FILE="build.zig.zon"

if [ ! -f "$ZON_FILE" ]; then
    echo "Error: $ZON_FILE not found in the current directory."
    exit 1
fi

# Extract current version
CURRENT_VERSION=$(awk -F '"' '/\.version =/ {print $2}' "$ZON_FILE")

if [ -z "$CURRENT_VERSION" ]; then
    echo "Error: Could not extract version from $ZON_FILE"
    exit 1
fi

# Split version into components
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Bump the version
if [ "$BUMP_TYPE" == "major" ]; then
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
elif [ "$BUMP_TYPE" == "minor" ]; then
    MINOR=$((MINOR + 1))
    PATCH=0
elif [ "$BUMP_TYPE" == "patch" ]; then
    PATCH=$((PATCH + 1))
else
    echo "Error: Invalid bump type '$BUMP_TYPE'. Use 'major', 'minor', or 'patch'."
    exit 1
fi

NEW_VERSION="$MAJOR.$MINOR.$PATCH"

echo "Bumping version from $CURRENT_VERSION to $NEW_VERSION..."

# Update build.zig.zon
sed "s/\.version = \"$CURRENT_VERSION\"/\.version = \"$NEW_VERSION\"/" "$ZON_FILE" > "${ZON_FILE}.tmp"
mv "${ZON_FILE}.tmp" "$ZON_FILE"

# Commit the change
git add "$ZON_FILE"
git commit -m "chore: bump version to $NEW_VERSION"

# Tag the release
TAG_NAME="v$NEW_VERSION"
git tag "$TAG_NAME"

echo "Successfully bumped to $NEW_VERSION and created tag $TAG_NAME"
echo "Pushing changes and tag to origin..."

# Push to trigger GitHub Actions
git push origin main
git push origin "$TAG_NAME"

echo "Done!"
