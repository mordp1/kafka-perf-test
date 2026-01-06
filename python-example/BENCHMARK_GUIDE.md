# Kafka Benchmark Script - Quick Start Guide

This automated benchmark suite tests Kafka performance with different configurations and generates beautiful HTML reports with interactive charts.

## 🚀 Quick Start

### Prerequisites

1. **Kafka cluster running** with topics created (see main README.md)
2. **Python 3.8+** installed
3. **Kafka binaries** in PATH or specified via `KAFKA_BIN_PATH`

### Installation

```bash
# Install Python dependencies
pip install -r requirements.txt

# Or use the provided script (creates virtual environment automatically)
chmod +x run_benchmark.sh
./run_benchmark.sh
```

## 📊 Running Benchmarks

### Option 1: Using the Shell Script (Recommended)

```bash
# Run with default settings
./run_benchmark.sh

# Customize settings via environment variables
export BOOTSTRAP_SERVERS="localhost:9092"
export NUM_RECORDS=500000
export RECORD_SIZE=2048
export OUTPUT_DIR="./my_results"
./run_benchmark.sh
```

### Option 2: Direct Python Execution

```bash
# Basic usage
python3 kafka_benchmark.py

# Custom configuration
python3 kafka_benchmark.py \
    --bootstrap-servers localhost:9092,localhost:9093 \
    --kafka-bin /opt/kafka/bin \
    --output-dir ./results \
    --num-records 2000000 \
    --record-size 512
```

## 🎯 What Gets Tested

The script automatically tests these configurations:

1. **1 Partition, RF=1** - Baseline single partition performance
2. **1 Partition, RF=3** - Impact of replication on single partition
3. **3 Partitions, RF=3** - Small scale-out test
4. **12 Partitions, RF=3** - Medium scale-out test  
5. **30 Partitions, RF=3** - Large scale-out test

## 📈 Output Files

After running, you'll get:

1. **JSON Results** - `benchmark_results_TIMESTAMP.json`
   - Raw performance data
   - Can be used for further analysis
   
2. **HTML Report** - `benchmark_report_TIMESTAMP.html`
   - Interactive charts comparing all tests
   - Summary statistics and key insights
   - Throughput, latency, and performance metrics
   - Open in any web browser

### Sample Report Contents

- **Throughput Comparison** - MB/sec across all tests
- **Records Per Second** - Message rate comparison
- **Latency Analysis** - Average and maximum latency
- **Throughput vs Latency** - Trade-off visualization
- **Data Volume** - Total data processed per test
- **Summary Table** - Topic-level performance comparison

## 🔧 Configuration Options

### Command Line Arguments

```bash
python3 kafka_benchmark.py \
    --bootstrap-servers SERVERS  # Kafka brokers (default: localhost:29092,localhost:39092,localhost:49092)
    --kafka-bin PATH            # Path to Kafka bin directory (optional)
    --output-dir PATH           # Output directory (default: current dir)
    --num-records N             # Records per test (default: 1000000)
    --record-size N             # Record size in bytes (default: 1024)
```

### Environment Variables (for shell script)

- `BOOTSTRAP_SERVERS` - Kafka bootstrap servers
- `KAFKA_BIN_PATH` - Path to Kafka bin directory
- `OUTPUT_DIR` - Output directory for results
- `NUM_RECORDS` - Number of records per test
- `RECORD_SIZE` - Size of each record in bytes

## 📝 Examples

### Example 1: Quick Test with Fewer Records

```bash
python3 kafka_benchmark.py --num-records 100000 --record-size 512
```

### Example 2: Large-Scale Test

```bash
python3 kafka_benchmark.py --num-records 5000000 --record-size 2048
```

### Example 3: Custom Kafka Installation

```bash
python3 kafka_benchmark.py \
    --kafka-bin /opt/confluent/bin \
    --bootstrap-servers kafka1:9092,kafka2:9092,kafka3:9092
```

### Example 4: Using Shell Script with Custom Settings

```bash
export BOOTSTRAP_SERVERS="10.0.1.10:9092,10.0.1.11:9092,10.0.1.12:9092"
export NUM_RECORDS=2000000
export KAFKA_BIN_PATH="/usr/local/kafka/bin"
./run_benchmark.sh
```

## 🎨 Viewing Results

### Opening the HTML Report

```bash
# macOS
open benchmark_results/benchmark_report_*.html

# Linux
xdg-open benchmark_results/benchmark_report_*.html

# Windows
start benchmark_results/benchmark_report_*.html
```

### What to Look For in Results

1. **Baseline Throughput** (p1-rf1) - Your maximum per-partition capacity
2. **Replication Impact** (p1-rf1 vs p1-rf3) - Cost of replication
3. **Scaling Efficiency** (p3, p12, p30) - How well partitions scale
4. **Latency Patterns** - Trade-offs between throughput and latency

## 🛠️ Troubleshooting

### "Command not found: kafka-producer-perf-test.sh"

Solution: Specify Kafka bin path
```bash
python3 kafka_benchmark.py --kafka-bin /path/to/kafka/bin
```

### "Connection refused to broker"

Solution: Verify Kafka is running and check bootstrap servers
```bash
# Test connection
echo "test" | kafka-console-producer.sh --bootstrap-server localhost:9092 --topic test-topic
```

### "ModuleNotFoundError: No module named 'pandas'"

Solution: Install dependencies
```bash
pip install -r requirements.txt
```

### Topics Don't Exist

Solution: Create topics first (see main README.md)
```bash
kafka-topics.sh --create --bootstrap-server localhost:9092 \
    --topic p1-rf1 --partitions 1 --replication-factor 1
# ... create other topics
```

## 🔍 Advanced Usage

### Running Specific Tests Only

Modify `kafka_benchmark.py` to customize `test_configs` list:

```python
test_configs = [
    {
        "topic": "my-custom-topic",
        "num_records": 1000000,
        "record_size": 1024,
        "acks": "all",
        "test_name": "My Custom Test"
    }
]
```

### Integrating with CI/CD

```bash
#!/bin/bash
# Example CI/CD integration
./run_benchmark.sh
if [ $? -eq 0 ]; then
    echo "Benchmark passed"
    # Upload results to artifact storage
    aws s3 cp benchmark_results/*.html s3://my-bucket/benchmarks/
else
    echo "Benchmark failed"
    exit 1
fi
```

## 📚 Understanding the Metrics

- **Throughput (MB/sec)** - Data volume processed per second
- **Records/sec** - Number of messages processed per second
- **Avg Latency** - Average time from send to acknowledgment
- **Max Latency** - Worst-case latency observed
- **P50/P95/P99** - Latency percentiles (50th, 95th, 99th)

## 💡 Tips for Video Recording

1. Start with small `--num-records` (e.g., 100000) for quick demos
2. Use `--record-size 1024` for realistic 1KB messages
3. Run tests in this order: p1-rf1 → p1-rf3 → p3-rf3 → p12-rf3 → p30-rf3
4. Show the HTML report in a browser - it's interactive!
5. Point out the throughput vs latency trade-off chart
6. Compare RF=1 vs RF=3 to explain replication overhead

## 🤝 Contributing

Feel free to enhance the script with:
- Consumer performance tests
- Different ACK levels comparison
- Compression codec tests
- Custom metrics and charts

## 📄 License

MIT License - Free to use and modify
