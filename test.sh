#!/bin/bash

echo "Running ETL tests..."

# Set the PYTHONPATH to the current directory
export PYTHONPATH=$(pwd)

# Run only ETL tests
pytest tests/ --maxfail=1 --disable-warnings -q

