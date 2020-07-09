#!/bin/sh
# Fall back to a shell if default nix-shell is exited:
"$HOME/.nix-profile/bin/nix-shell" /nixenv/nixuser/dev.nix; sh
