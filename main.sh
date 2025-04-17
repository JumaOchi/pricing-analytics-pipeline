#!/bin/bash

set -e  # Exit on error

echo " Cleaning up old files"
rm -f /home/juma/pricing_analysis/pricing-analytics-pipeline/data/staged/*.csv

# adding modules paths
export PYTHONPATH="${PYTHONPATH}:$(pwd)"

echo " Extracting data..."
python3 pipeline/extract.py

echo " Transforming data..."
python3 pipeline/transform.py

echo " Loading data to PostgreSQL..."
python3 pipeline/load.py

echo " ETL pipeline complete!"
