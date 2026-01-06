#!/bin/bash
# Wrapper script to run Kafka benchmarks

set -e

# Configuration
BOOTSTRAP_SERVERS="${BOOTSTRAP_SERVERS:-localhost:29092,localhost:39092,localhost:49092}"
KAFKA_BIN="${KAFKA_BIN_PATH:-}"
OUTPUT_DIR="${OUTPUT_DIR:-./benchmark_results}"
NUM_RECORDS="${NUM_RECORDS:-1000000}"
RECORD_SIZE="${RECORD_SIZE:-1024}"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}Kafka Benchmark Test Suite${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is not installed"
    exit 1
fi

# Check if virtual environment exists, create if not
if [ ! -d "venv" ]; then
    echo -e "${GREEN}Creating Python virtual environment...${NC}"
    python3 -m venv venv
fi

# Activate virtual environment
echo -e "${GREEN}Activating virtual environment...${NC}"
source venv/bin/activate

# Install/upgrade dependencies
echo -e "${GREEN}Installing dependencies...${NC}"
pip install -q --upgrade pip
pip install -q -r requirements.txt

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Run benchmark
echo -e "${GREEN}Starting benchmark tests...${NC}"
echo ""

python3 kafka_benchmark.py \
    --bootstrap-servers "$BOOTSTRAP_SERVERS" \
    --kafka-bin "$KAFKA_BIN" \
    --output-dir "$OUTPUT_DIR" \
    --num-records "$NUM_RECORDS" \
    --record-size "$RECORD_SIZE"

# Deactivate virtual environment
deactivate

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Benchmark complete! Check $OUTPUT_DIR for results${NC}"
echo -e "${GREEN}================================================${NC}"
