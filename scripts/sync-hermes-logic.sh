#!/bin/bash
# Hermes Logic Sync Script
# Collects Soul, Skills, and Config from all profiles and commits to the hermes-data repo.

REPO_DIR="/home/hermes/hermes-data-repo"
HERMES_HOME="/home/hermes/.hermes"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Starting Hermes Logic Sync at $TIMESTAMP"

cd "$REPO_DIR" || exit 1

# Ensure we have the latest from remote
git pull origin main --quiet || echo "Warning: Could not pull from remote. Proceeding with local sync."

sync_profile() {
    profile_name="$1"
    profile_path="$2"

    [ -d "$profile_path" ] || return 0

    echo "Syncing profile: $profile_name"

    profile_repo_dir="$REPO_DIR/profiles/$profile_name"
    mkdir -p "$profile_repo_dir/skills"

    # 1. Sync Soul.md
    if [ -f "$profile_path/SOUL.md" ]; then
        cp "$profile_path/SOUL.md" "$profile_repo_dir/soul.md"
    fi

    # 2. Sync Skills
    if [ -d "$profile_path/skills" ]; then
        cp -r "$profile_path/skills/"* "$profile_repo_dir/skills/" 2>/dev/null || true
    fi

    # 3. Sync Config (if exists)
    if [ -f "$profile_path/config.yaml" ]; then
        cp "$profile_path/config.yaml" "$profile_repo_dir/config.yaml"
    fi
}

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
