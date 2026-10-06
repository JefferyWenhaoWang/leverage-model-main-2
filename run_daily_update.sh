#!/bin/zsh

cd ~/research/leverage-model || exit 1

source /opt/anaconda3/bin/activate base

echo "=== Updating data ==="
python3 update_data.py

echo "=== Running model ==="
python3 sqqq_leverage_band_model.py

echo "=== Done ==="
