#!/usr/bin/env bash
# The same checks as GitLab's isolated test-app job; no Docker or real Git pushes.
set -euo pipefail
Rscript tests/test_app.R
python3 -m unittest discover -s tests -p 'test_*.py' -v
for script in scripts/*.sh; do bash -n "$script"; done
