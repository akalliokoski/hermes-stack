#!/bin/bash
# Hermes Logic Sync Script
# Collects shared SOUL/skills plus profile SOUL, skills, and config into the hermes-data repo.

set -euo pipefail

REPO_DIR="/home/hermes/hermes-data-repo"
HERMES_HOME="/home/hermes/.hermes"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

sync_tree() {
    src="$1"
    dest="$2"

    mkdir -p "$dest"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete "$src/" "$dest/"
    else
        rm -rf "$dest"
        mkdir -p "$dest"
        cp -a "$src/." "$dest/"
    fi
}

echo "Starting Hermes Logic Sync at $TIMESTAMP"

cd "$REPO_DIR" || exit 1

# Ensure we have the latest from remote
git pull origin main --quiet || echo "Warning: Could not pull from remote. Proceeding with local sync."

sync_shared_logic() {
    shared_repo_dir="$REPO_DIR/shared"
    mkdir -p "$shared_repo_dir"

    if [ -d "$HERMES_HOME/shared/soul" ]; then
        echo "Syncing shared soul sources"
        sync_tree "$HERMES_HOME/shared/soul" "$shared_repo_dir/soul"
    else
        rm -rf "$shared_repo_dir/soul"
    fi

    if [ -d "$HERMES_HOME/shared/skills" ]; then
        echo "Syncing shared skills"
        sync_tree "$HERMES_HOME/shared/skills" "$shared_repo_dir/skills"
    else
        rm -rf "$shared_repo_dir/skills"
    fi
}

sync_profile() {
    profile_name="$1"
    profile_path="$2"

    [ -d "$profile_path" ] || return 0

    echo "Syncing profile: $profile_name"

    profile_repo_dir="$REPO_DIR/profiles/$profile_name"
    mkdir -p "$profile_repo_dir"

    # 1. Sync Soul.md
    if [ -f "$profile_path/SOUL.md" ]; then
        cp "$profile_path/SOUL.md" "$profile_repo_dir/soul.md"
    fi

    # 2. Sync Skills
    if [ -d "$profile_path/skills" ]; then
        sync_tree "$profile_path/skills" "$profile_repo_dir/skills"
    else
        rm -rf "$profile_repo_dir/skills"
    fi

    # 3. Sync Config (if exists)
    if [ -f "$profile_path/config.yaml" ]; then
        cp "$profile_path/config.yaml" "$profile_repo_dir/config.yaml"
    fi
}

sync_shared_logic

# Sync default profile first (stored directly under ~/.hermes, not ~/.hermes/profiles/default)
sync_profile "default" "$HERMES_HOME"

# Sync named profiles
for profile_path in "$HERMES_HOME/profiles/"*; do
    if [ -d "$profile_path" ]; then
        profile_name=$(basename "$profile_path")
        sync_profile "$profile_name" "$profile_path"
    fi
done

# Check for changes
if [[ -n $(git status --porcelain) ]]; then
    echo "Changes detected. Committing..."
    git add .
    git commit -m "chore: sync hermes logic $TIMESTAMP"
    git push origin main
    echo "Sync complete and pushed to GitHub."
else
    echo "No changes detected. Nothing to commit."
fi
