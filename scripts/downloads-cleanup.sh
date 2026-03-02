#!/usr/bin/env bash
set -euo pipefail

# Connect to seedbox for marked items
# Looks in LOCAL_BASE and deletes matching folder
# Flock to avoid concurrency issues
