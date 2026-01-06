#!/bin/bash

# Create Kafka Test Topics
# Creates topics with different partition/replication configurations for benchmarking

set -e

BOOTSTRAP_SERVERS="${BOOTSTRAP_SERVERS:-localhost:29092,localhost:39092,localhost:49092}"
KAFKA_BIN="${KAFKA_BIN:-}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}Creating Kafka Benchmark Topics${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Find Kafka binaries
if [ -n "$KAFKA_BIN" ]; then
    KAFKA_TOPICS="$KAFKA_BIN/kafka-topics.sh"
else
    if command -v kafka-topics.sh &> /dev/null; then
        KAFKA_TOPICS="kafka-topics.sh"
    else
        echo -e "${RED}✗ Could not find kafka-topics.sh${NC}"
        echo "Set KAFKA_BIN environment variable or add Kafka to PATH"
        exit 1
    fi
fi

echo -e "${GREEN}✓ Using Kafka binaries: $(dirname $KAFKA_TOPICS)${NC}"
echo -e "${GREEN}✓ Bootstrap servers: $BOOTSTRAP_SERVERS${NC}"
echo ""

# Function to create topic
create_topic() {
    local topic=$1
    local partitions=$2
    local replication=$3
    
    echo -e "Creating topic: ${BLUE}$topic${NC} (Partitions: $partitions, RF: $replication)"
    
    $KAFKA_TOPICS --create \
        --bootstrap-server "$BOOTSTRAP_SERVERS" \
        --topic "$topic" \
        --partitions "$partitions" \
        --replication-factor "$replication" \
        --config retention.ms=3600000 2>/dev/null && \
        echo -e "${GREEN}✓ Created${NC}" || \
        echo -e "${RED}✗ Already exists or failed${NC}"
}

# Create benchmark topics
create_topic "p1-rf1" 1 1
create_topic "p1-rf3" 1 3
create_topic "p3-rf3" 3 3
create_topic "p12-rf3" 12 3
create_topic "p30-rf3" 30 3

echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${GREEN}✓ Topic creation complete!${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo "Verify topics with:"
echo "  $KAFKA_TOPICS --list --bootstrap-server $BOOTSTRAP_SERVERS"
echo ""
echo "Describe topics with:"
echo "  $KAFKA_TOPICS --describe --bootstrap-server $BOOTSTRAP_SERVERS"
echo ""
