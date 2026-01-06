# Kafka Benchmark 🚀

Clean, production-ready benchmark suite for testing both Kafka producer and consumer performance.

## ✨ Features

- ✅ **Producer Performance Testing** - Throughput, latency, records/sec
- ✅ **Consumer Performance Testing** - Throughput, records/sec, fetch metrics
- ✅ **Beautiful HTML Reports** - Interactive charts with Plotly
- ✅ **Topic Ordering** - Results sorted logically (p1-rf1, p1-rf3, p3-rf3, p12-rf3, p30-rf3)
- ✅ **Producer vs Consumer Comparison** - Side-by-side performance analysis
- ✅ **Flexible Configuration** - Command-line options for all parameters

## 🚀 Quick Start

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. Run Benchmarks

**Producer AND Consumer tests:**
```bash
./run_benchmark.sh
```

**Producer tests ONLY:**
```bash
python3 kafka_benchmark.py --skip-consumer
```

**Custom configuration:**
```bash
python3 kafka_benchmark.py \
    --bootstrap-servers localhost:9092,localhost:9093 \
    --num-records 500000 \
    --record-size 2048 \
    --output-dir ./my_results
```

## 📊 Output Files

After running, you'll get:

1. **`benchmark_results_TIMESTAMP.json`** - Raw performance data
2. **`benchmark_report_TIMESTAMP.html`** - Interactive HTML report with charts

## 🎯 What Gets Tested

### Producer Tests
- 1 Partition, RF=1 (Baseline)
- 1 Partition, RF=3 (Replication impact)
- 3 Partitions, RF=3
- 12 Partitions, RF=3  
- 30 Partitions, RF=3

### Consumer Tests
- Same topics as producers
- Single-threaded consumers
- Measures throughput, records/sec, fetch times

## 📈 Report Contents

The HTML report includes:

- **Summary Statistics** - Total records, average/peak throughput, best configuration
- **Producer Performance Table** - Throughput, records/sec, latency by topic
- **Consumer Performance Table** - Throughput, records/sec by topic
- **Interactive Charts**:
  - Producer throughput comparison
  - Producer latency analysis
  - Consumer throughput comparison
  - Producer vs Consumer side-by-side
  - And more!

## 🔧 Command Line Options

```bash
python3 kafka_benchmark.py --help

Options:
  --bootstrap-servers SERVERS   Kafka brokers (default: localhost:29092,...)
  --kafka-bin PATH             Path to Kafka bin directory (optional)
  --output-dir PATH            Output directory (default: current dir)
  --num-records N              Records per test (default: 1000000)
  --record-size N              Record size in bytes (default: 1024)
  --skip-consumer              Skip consumer tests (producer only)
```

## 📝 Examples

### Quick Test (fewer records)
```bash
python3 kafka_benchmark.py --num-records 100000
```

### Large-Scale Test
```bash
python3 kafka_benchmark.py --num-records 5000000 --record-size 2048
```

### Custom Kafka Installation
```bash
python3 kafka_benchmark.py \
    --kafka-bin /opt/kafka/bin \
    --bootstrap-servers kafka1:9092,kafka2:9092,kafka3:9092
```

### Producer Only (Skip Consumer Tests)
```bash
python3 kafka_benchmark.py --skip-consumer
```

## 🎬 Viewing Results

```bash
# macOS
open benchmark_report_*.html

# Linux
xdg-open benchmark_report_*.html

# Windows
start benchmark_report_*.html
```

## 💡 Key Improvements in V2

- ✅ **Clean Codebase** - Built from scratch, no legacy code
- ✅ **Proper Topic Ordering** - Results sorted logically, not alphabetically
- ✅ **Better Error Handling** - Graceful failures and clear error messages
- ✅ **Flexible Testing** - Can run producer-only or both
- ✅ **Enhanced Charts** - More informative visualizations
- ✅ **Separate Test Types** - Producer and consumer clearly distinguished

## 🛠️ Troubleshooting

### "Command not found: kafka-producer-perf-test.sh"
```bash
python3 kafka_benchmark.py --kafka-bin /path/to/kafka/bin
```

### "Connection refused to broker"
```bash
# Verify Kafka is running
kafka-topics.sh --bootstrap-server localhost:9092 --list
```

### Consumer tests fail but producer works
This is normal if topics don't have data yet. Run producer tests first to populate topics.

## 📚 For More Details

See [BENCHMARK_GUIDE.md](BENCHMARK_GUIDE.md) for comprehensive documentation.

## 🤝 Differences from V1

- **V1**: Had code corruption issues, consumer tests mixed with producer logic
- **V2**: Clean separation, proper error handling, better reporting
- **V2**: Can skip consumer tests with `--skip-consumer` flag
- **V2**: More reliable parsing of consumer output

---

**Ready to benchmark your Kafka cluster? Run `./run_benchmark.sh` and watch the magic! ✨**
