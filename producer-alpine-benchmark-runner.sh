#!/bin/sh

# Kafka Benchmark Runner - Native Performance Testing
# Compatible with Alpine Linux / BusyBox sh
# Runs kafka-producer-perf-test.sh and saves results for comparison

set -e

# Configuration
BOOTSTRAP_SERVERS="${BOOTSTRAP_SERVERS:-localhost:29092,localhost:39092,localhost:49092}"
KAFKA_BIN="${KAFKA_BIN:-}"
NUM_RECORDS="${NUM_RECORDS:-1000000}"
RECORD_SIZE="${RECORD_SIZE:-1024}"
CLIENT_CONFIG="${CLIENT_CONFIG:-}"  # Optional: path to producer.properties file
RESULTS_DIR="./benchmark_results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="${RESULTS_DIR}/results_${TIMESTAMP}.csv"
RAW_DIR="${RESULTS_DIR}/raw"

# Topics to test (in logical order)
TOPICS="
p1-rf1
p1-rf3
p3-rf3
p12-rf3
p30-rf3
"

# Colors for output (only if terminal supports it)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

print_header() {
    printf "${BLUE}================================================${NC}\n"
    printf "${BLUE}%s${NC}\n" "$1"
    printf "${BLUE}================================================${NC}\n"
}

print_info()    { printf "${GREEN}✓${NC} %s\n" "$1"; }
print_warning() { printf "${YELLOW}⚠${NC} %s\n" "$1"; }
print_error()   { printf "${RED}✗${NC} %s\n" "$1"; }

# ---------------------------------------------------------------
# Validate bootstrap.servers connectivity before running tests
# ---------------------------------------------------------------
check_connectivity() {
    print_info "Checking broker connectivity..."

    # Determine the servers to check:
    # If a CLIENT_CONFIG is provided, read bootstrap.servers from it.
    # Otherwise fall back to the BOOTSTRAP_SERVERS env variable.
    local servers="$BOOTSTRAP_SERVERS"
    if [ -n "$CLIENT_CONFIG" ] && [ -f "$CLIENT_CONFIG" ]; then
        local cfg_servers
        cfg_servers=$(grep -E '^bootstrap\.servers' "$CLIENT_CONFIG" | head -1 | sed 's/.*=[ ]*//')
        if [ -n "$cfg_servers" ]; then
            servers="$cfg_servers"
            print_info "Bootstrap servers from config: $servers"
        else
            print_warning "bootstrap.servers not found in $CLIENT_CONFIG — falling back to env: $servers"
        fi
    else
        print_info "Bootstrap servers from env: $servers"
    fi

    local all_ok=true
    # Split comma-separated list
    local IFS_BAK="$IFS"
    IFS=','
    for addr in $servers; do
        IFS="$IFS_BAK"
        # Strip leading/trailing whitespace
        addr=$(echo "$addr" | tr -d ' ')
        local host="${addr%:*}"
        local port="${addr#*:}"

        if nc -z -w 3 "$host" "$port" 2>/dev/null; then
            print_info "  Reachable: $addr"
        else
            print_error "  NOT reachable: $addr"
            all_ok=false
        fi
        IFS=','
    done
    IFS="$IFS_BAK"

    if [ "$all_ok" = false ]; then
        print_error "One or more brokers are not reachable."
        print_error "Common fixes:"
        printf "  1. If brokers are other Docker containers, use container names, not 'localhost':\n"
        printf "       bootstrap.servers=kafka1:9092,kafka2:9092,kafka3:9092\n"
        printf "  2. Make sure this container is on the same Docker network as the brokers.\n"
        printf "  3. Check the internal vs external port: inside Docker use 9092, not 29092.\n"
        printf "  4. Set via env:  BOOTSTRAP_SERVERS=kafka1:9092 ./producer-benchmark-runner.sh\n"
        printf "     Or put it in your CLIENT_CONFIG file:\n"
        printf "       echo 'bootstrap.servers=kafka1:9092' >> /tmp/client.properties\n"
        exit 1
    fi

    print_info "All brokers reachable."
}

# ---------------------------------------------------------------
# Find Kafka binaries
# ---------------------------------------------------------------
find_kafka_bin() {
    if [ -n "$KAFKA_BIN" ] && [ -x "$KAFKA_BIN/kafka-producer-perf-test.sh" ]; then
        echo "$KAFKA_BIN"
        return 0
    fi

    for path in /opt/kafka/bin /usr/local/kafka/bin "$HOME/kafka/bin" ./bin ../bin; do
        if [ -x "$path/kafka-producer-perf-test.sh" ]; then
            echo "$path"
            return 0
        fi
    done

    if command -v kafka-producer-perf-test.sh > /dev/null 2>&1; then
        dirname "$(command -v kafka-producer-perf-test.sh)"
        return 0
    fi

    return 1
}

# ---------------------------------------------------------------
# Initialize results directory and CSV header
# ---------------------------------------------------------------
init_results_dir() {
    mkdir -p "$RESULTS_DIR"
    mkdir -p "$RAW_DIR"
    printf "timestamp,topic,partitions,replication_factor,num_records,record_size,throughput_mb_sec,avg_latency_ms,max_latency_ms,p50_latency_ms,p95_latency_ms,p99_latency_ms,p999_latency_ms,records_per_sec\n" > "$RESULT_FILE"
}

# ---------------------------------------------------------------
# Parse producer perf test output and write results
# Uses awk only — fully compatible with BusyBox on Alpine.
# No grep -oE, no <<< here-strings.
# ---------------------------------------------------------------
parse_producer_output() {
    local output="$1"
    local topic="$2"

    local partitions
    local rf
    partitions=$(echo "$topic" | sed -n 's/.*p\([0-9]*\).*/\1/p')
    rf=$(echo "$topic" | sed -n 's/.*rf\([0-9]*\).*/\1/p')

    # All parsing, CSV writing and display happen inside awk.
    # Fields are matched by their neighbouring keyword tokens, so layout
    # differences (integer vs float) are handled naturally.
    echo "$output" | awk \
        -v topic="$topic" \
        -v partitions="$partitions" \
        -v rf="$rf" \
        -v num_records="$NUM_RECORDS" \
        -v record_size="$RECORD_SIZE" \
        -v timestamp="$TIMESTAMP" \
        -v result_file="$RESULT_FILE" '
    /records sent/ {
        for (i = 1; i <= NF; i++) {
            if ($i == "records" && $(i+1) == "sent,")
                records_sent = $(i-1)

            if ($i == "records/sec")
                rps = $(i-1)

            # Throughput sits just before "MB/sec)," — strip the leading "("
            if ($i == "MB/sec)," || $i == "MB/sec).") {
                v = $(i-1)
                gsub(/[^0-9.]/, "", v)
                throughput = v
            }

            if ($i == "ms" && $(i+1) == "avg")  avg = $(i-1)
            if ($i == "ms" && $(i+1) == "max")  max = $(i-1)

            # Percentiles — tokens differ slightly across Kafka versions
            if ($i == "ms" && ($(i+1) == "50th,"  || $(i+1) == "50th"))  p50  = $(i-1)
            if ($i == "ms" && ($(i+1) == "95th,"  || $(i+1) == "95th"))  p95  = $(i-1)
            if ($i == "ms" && ($(i+1) == "99th,"  || $(i+1) == "99th"))  p99  = $(i-1)
            if ($i == "ms" && ($(i+1) == "99.9th."|| $(i+1) == "99.9th")) p999 = $(i-1)
        }
    }
    END {
        # Guard: if no data was parsed, print a clear warning
        if (records_sent == "") {
            print "WARNING: could not parse producer output for topic " topic > "/dev/stderr"
            print "         Check the raw log file in the raw/ directory."         > "/dev/stderr"
        }

        # Append CSV row
        print timestamp "," topic "," partitions "," rf "," num_records "," record_size "," \
              throughput "," avg "," max "," p50 "," p95 "," p99 "," p999 "," rps \
              >> result_file

        # Human-readable display
        print "Topic: "           topic
        print "Records Sent: "    records_sent
        print "Throughput: "      throughput " MB/sec"
        print "Records/sec: "     rps
        print "Avg Latency: "     avg " ms"
        print "Max Latency: "     max " ms"
        print "P50/P95/P99/P99.9: " p50 "/" p95 "/" p99 "/" p999 " ms"
    }
    '
}

# ---------------------------------------------------------------
# Run producer test for one topic
# ---------------------------------------------------------------
run_producer_test() {
    local topic="$1"
    local kafka_bin="$2"

    print_info "Testing topic: $topic"

    local raw_output_file="${RAW_DIR}/${topic}_${TIMESTAMP}.log"
    local output=""

    if [ -n "$CLIENT_CONFIG" ] && [ -f "$CLIENT_CONFIG" ]; then
        print_info "Using producer config: $CLIENT_CONFIG"
        output=$("$kafka_bin/kafka-producer-perf-test.sh" \
            --topic "$topic" \
            --num-records "$NUM_RECORDS" \
            --record-size "$RECORD_SIZE" \
            --throughput -1 \
            --producer.config "$CLIENT_CONFIG" 2>&1 | tee "$raw_output_file")
    else
        output=$("$kafka_bin/kafka-producer-perf-test.sh" \
            --topic "$topic" \
            --num-records "$NUM_RECORDS" \
            --record-size "$RECORD_SIZE" \
            --throughput -1 \
            --producer-props bootstrap.servers="$BOOTSTRAP_SERVERS" acks=1 2>&1 | tee "$raw_output_file")
    fi

    # Abort early if Kafka itself reported an error
    if echo "$output" | grep -q "Exception\|ERROR\|Error"; then
        print_error "Kafka error for topic $topic — see raw log: $raw_output_file"
        echo "$output" | grep -E "Exception|ERROR|Error" | head -5
        return 1
    fi

    printf "\n"
    parse_producer_output "$output" "$topic"
    printf "\n"
}

# ---------------------------------------------------------------
# Generate text + HTML report
# ---------------------------------------------------------------
generate_report() {
    local report_file="${RESULTS_DIR}/report_${TIMESTAMP}.txt"
    local html_report="${RESULTS_DIR}/report_${TIMESTAMP}.html"

    print_header "Generating Comparison Report"

    {
        printf "KAFKA BENCHMARK RESULTS\n"
        printf "=======================\n"
        printf "Timestamp: %s\n" "$TIMESTAMP"
        printf "Records per Test: %s\n" "$NUM_RECORDS"
        printf "Record Size: %s bytes\n" "$RECORD_SIZE"
        printf "\nRESULTS SUMMARY\n"
        printf "===============\n\n"

        tail -n +2 "$RESULT_FILE" | while IFS=',' read -r ts topic part rf num_rec rec_size throughput avg_lat max_lat p50 p95 p99 p999 rps; do
            printf "Topic: %s (Partitions: %s, RF: %s)\n" "$topic" "$part" "$rf"
            printf "  Throughput:    %s MB/sec\n" "$throughput"
            printf "  Records/sec:   %s\n" "$rps"
            printf "  Avg Latency:   %s ms\n" "$avg_lat"
            printf "  P50/P95/P99:   %s/%s/%s ms\n\n" "$p50" "$p95" "$p99"
        done

        printf "PERFORMANCE RANKING (by Throughput)\n"
        printf "====================================\n"
        tail -n +2 "$RESULT_FILE" | sort -t',' -k7 -rn | while IFS=',' read -r ts topic part rf num_rec rec_size throughput avg_lat max_lat p50 p95 p99 p999 rps; do
            printf "  %s: %s MB/sec\n" "$topic" "$throughput"
        done

        printf "\nLOWEST LATENCY (by Avg Latency)\n"
        printf "================================\n"
        tail -n +2 "$RESULT_FILE" | sort -t',' -k8 -n | while IFS=',' read -r ts topic part rf num_rec rec_size throughput avg_lat max_lat p50 p95 p99 p999 rps; do
            printf "  %s: %s ms\n" "$topic" "$avg_lat"
        done

    } | tee "$report_file"

    generate_html_report "$html_report"

    print_info "Text report: $report_file"
    print_info "HTML report: $html_report"
    print_info "CSV data:    $RESULT_FILE"
}

# ---------------------------------------------------------------
# Generate HTML report with embedded Plotly charts
# ---------------------------------------------------------------
generate_html_report() {
    local html_file="$1"

    cat > "$html_file" << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Kafka Benchmark Results</title>
    <script src="https://cdn.plot.ly/plotly-2.27.0.min.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px; margin-bottom: 30px; }
        .header h1 { margin: 0 0 10px 0; }
        .container { max-width: 1400px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .summary-card { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; }
        .summary-card h3 { margin: 0 0 8px 0; font-size: 13px; opacity: .85; }
        .summary-card .value { font-size: 26px; font-weight: bold; }
        .summary-card .label { font-size: 11px; opacity: .75; margin-top: 4px; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background: #667eea; color: white; padding: 12px; text-align: left; }
        td { padding: 12px; border-bottom: 1px solid #ddd; }
        tr:hover { background: #f5f5f5; }
        .chart { margin: 30px 0; padding: 10px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .best { color: #28a745; font-weight: bold; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🚀 Kafka Benchmark Results</h1>
        <p>kafka-producer-perf-test.sh — Performance Analysis</p>
    </div>
    <div class="container">
        <div id="summary" class="summary"></div>
        <h2>📊 Detailed Results</h2>
        <table>
            <thead>
                <tr><th>Topic</th><th>Partitions</th><th>RF</th><th>Throughput (MB/s)</th><th>Records/sec</th><th>Avg Latency (ms)</th><th>P99 (ms)</th></tr>
            </thead>
            <tbody id="resultsBody"></tbody>
        </table>
        <div class="chart" id="throughputChart"></div>
        <div class="chart" id="latencyChart"></div>
        <div class="chart" id="percentileChart"></div>
    </div>
    <script>
CSV_DATA_PLACEHOLDER

        function parseCSV() {
            const lines = csvData.trim().split('\n');
            return lines.slice(1).map(line => {
                const v = line.split(',');
                return {
                    topic:        v[1],
                    partitions:   parseInt(v[2]),
                    rf:           parseInt(v[3]),
                    num_records:  parseInt(v[4]),
                    throughput:   parseFloat(v[6]),
                    avg_latency:  parseFloat(v[7]),
                    max_latency:  parseFloat(v[8]),
                    p50:          parseFloat(v[9]),
                    p95:          parseFloat(v[10]),
                    p99:          parseFloat(v[11]),
                    p999:         parseFloat(v[12]),
                    rps:          parseFloat(v[13])
                };
            });
        }

        function render() {
            const data = parseCSV();
            if (!data.length) return;

            const maxTP  = Math.max(...data.map(d => d.throughput));
            const minLat = Math.min(...data.map(d => d.avg_latency));
            const avgTP  = (data.reduce((s,d) => s + d.throughput, 0) / data.length).toFixed(2);
            const bestTopic = data.find(d => d.throughput === maxTP).topic;

            document.getElementById('summary').innerHTML = `
                <div class="summary-card"><h3>Topics Tested</h3><div class="value">${data.length}</div></div>
                <div class="summary-card"><h3>Average Throughput</h3><div class="value">${avgTP}</div><div class="label">MB/sec</div></div>
                <div class="summary-card"><h3>Peak Throughput</h3><div class="value">${maxTP.toFixed(2)}</div><div class="label">MB/sec — ${bestTopic}</div></div>
                <div class="summary-card"><h3>Best Avg Latency</h3><div class="value">${minLat.toFixed(2)}</div><div class="label">ms</div></div>
            `;

            const tbody = document.getElementById('resultsBody');
            data.forEach(row => {
                const tr = document.createElement('tr');
                tr.innerHTML = `
                    <td>${row.topic}</td>
                    <td>${row.partitions}</td>
                    <td>${row.rf}</td>
                    <td class="${row.throughput===maxTP?'best':''}">${row.throughput.toFixed(2)}</td>
                    <td>${row.rps.toFixed(0)}</td>
                    <td class="${row.avg_latency===minLat?'best':''}">${row.avg_latency.toFixed(2)}</td>
                    <td>${row.p99.toFixed(2)}</td>
                `;
                tbody.appendChild(tr);
            });

            // Throughput bar chart
            Plotly.newPlot('throughputChart', [{
                x: data.map(d => d.topic), y: data.map(d => d.throughput),
                type: 'bar', marker: { color: data.map(d => d.throughput), colorscale: 'Viridis' },
                text: data.map(d => d.throughput.toFixed(2) + ' MB/s'), textposition: 'outside'
            }], { title: 'Throughput (MB/sec)', xaxis:{title:'Topic'}, yaxis:{title:'MB/sec'}, height:400 });

            // Avg + P99 grouped bar
            Plotly.newPlot('latencyChart', [
                { x: data.map(d=>d.topic), y: data.map(d=>d.avg_latency), name:'Avg', type:'bar', marker:{color:'#667eea'} },
                { x: data.map(d=>d.topic), y: data.map(d=>d.p99),         name:'P99', type:'bar', marker:{color:'#764ba2'} }
            ], { title: 'Latency Comparison (ms)', barmode:'group', xaxis:{title:'Topic'}, yaxis:{title:'ms'}, height:400 });

            // Percentile lines
            Plotly.newPlot('percentileChart', [
                { x: data.map(d=>d.topic), y: data.map(d=>d.p50),  name:'P50',   type:'scatter', mode:'lines+markers' },
                { x: data.map(d=>d.topic), y: data.map(d=>d.p95),  name:'P95',   type:'scatter', mode:'lines+markers' },
                { x: data.map(d=>d.topic), y: data.map(d=>d.p99),  name:'P99',   type:'scatter', mode:'lines+markers' },
                { x: data.map(d=>d.topic), y: data.map(d=>d.p999), name:'P99.9', type:'scatter', mode:'lines+markers' }
            ], { title: 'Latency Percentiles (ms)', xaxis:{title:'Topic'}, yaxis:{title:'ms'}, height:400 });
        }

        window.addEventListener('DOMContentLoaded', render);
    </script>
</body>
</html>
HTMLEOF

    # Embed CSV data inline (works with file:// — no server needed)
    local tmp="${html_file}.tmp"
    awk -v csvfile="$RESULT_FILE" '
        /CSV_DATA_PLACEHOLDER/ {
            printf "        const csvData = `"
            while ((getline line < csvfile) > 0) {
                gsub(/`/, "\\`", line)
                gsub(/\$/, "\\$", line)
                print line
            }
            close(csvfile)
            printf "`;\n"
            next
        }
        { print }
    ' "$html_file" > "$tmp" && mv "$tmp" "$html_file"
}

# ---------------------------------------------------------------
# Main
# ---------------------------------------------------------------
main() {
    print_header "Kafka Native Benchmark Runner"

    # Find Kafka binaries
    print_info "Locating Kafka binaries..."
    KAFKA_BIN=$(find_kafka_bin) || {
        print_error "Could not find Kafka binaries. Set KAFKA_BIN=/path/to/kafka/bin"
        exit 1
    }
    print_info "Using Kafka binaries: $KAFKA_BIN"

    # Init output dir early so RAW_DIR exists for connectivity check logs
    init_results_dir
    print_info "Results directory: $RESULTS_DIR"

    if [ -n "$CLIENT_CONFIG" ] && [ -f "$CLIENT_CONFIG" ]; then
        print_info "Using config file: $CLIENT_CONFIG"
    else
        print_info "Bootstrap servers: $BOOTSTRAP_SERVERS"
    fi
    print_info "Records per test: $NUM_RECORDS"
    print_info "Record size: $RECORD_SIZE bytes"
    printf "\n"

    # Connectivity check — exits with a clear message if brokers unreachable
    check_connectivity
    printf "\n"

    # Run tests
    print_header "Running Benchmark Tests"
    for topic in $TOPICS; do
        [ -z "$topic" ] && continue
        run_producer_test "$topic" "$KAFKA_BIN" || print_warning "Skipping $topic due to error above"
        sleep 2
    done

    # Reports
    generate_report

    print_header "Benchmark Complete!"
    print_info "Open the HTML report:"
    printf "\n  open %s/report_%s.html\n\n" "$RESULTS_DIR" "$TIMESTAMP"
}

main "$@"
