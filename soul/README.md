Shared SOUL instructions
========================

Edit base.md for instructions shared by every Hermes profile.
Edit profiles/<name>.md for profile-specific instructions.

After changing either file, rerun:
  bash /opt/hermes/scripts/provision-profile.sh --sync-all-souls

Or update a single profile:
  bash /opt/hermes/scripts/provision-profile.sh --profile <name>
