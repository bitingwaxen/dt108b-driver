#!/bin/bash
set -euo pipefail
MODE="${1:-gap}"
sudo /opt/dt108b/venv/bin/dt108b-calibrate --mode "$MODE"
