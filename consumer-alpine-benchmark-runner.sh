#!/bin/sh

# Kafka Consumer Benchmark Runner - Native Performance Testing
# Compatible with Alpine Linux / BusyBox sh
# Runs kafka-consumer-perf-test.sh and saves results for comparison

set -e

# Configuration
BOOTSTRAP_SERVERS="${BOOTSTRAP_SERVERS:-localhost:29092,localhost:39092,localhost:49092}"
KAFKA_BIN="${KAFKA_BIN:-}"
NUM_MESSAGES="${NUM_MESSAGES:-1000000}"
CLIENT_CONFIG="${CLIENT_CONFIG:-}"  # Optional: path to consumer.properties file
RESULTS_DIR="./benchmark_results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="${RESULTS_DIR}/consumer_results_${TIMESTAMP}.csv"
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
    local IFS_BAK="$IFS"
    IFS=','
    for addr in $servers; do
        IFS="$IFS_BAK"
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
        printf "  4. Set via env:  BOOTSTRAP_SERVERS=kafka1:9092 ./consumer-benchmark-runner.sh\n"
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
    if [ -n "$KAFKA_BIN" ] && [ -x "$KAFKA_BIN/kafka-consumer-perf-test.sh" ]; then
        echo "$KAFKA_BIN"
        return 0
    fi

    for path in /opt/kafka/bin /usr/local/kafka/bin "$HOME/kafka/bin" ./bin ../bin; do
        if [ -x "$path/kafka-consumer-perf-test.sh" ]; then
            echo "$path"
            return 0
        fi
    done

    if command -v kafka-consumer-perf-test.sh > /dev/null 2>&1; then
        dirname "$(command -v kafka-consumer-perf-test.sh)"
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
    printf "timestamp,topic,partitions,replication_factor,num_messages,data_consumed_mb,throughput_mb_sec,messages_consumed,messages_per_sec,rebalance_time_ms,fetch_time_ms,fetch_mb_sec,fetch_msg_sec\n" > "$RESULT_FILE"
}

# ---------------------------------------------------------------
# Parse consumer perf test output and write results
# Consumer output is CSV:
# start.time, end.time, data.consumed.in.MB, MB.sec, data.consumed.in.nMsg,
# nMsg.sec, rebalance.time.ms, fetch.time.ms, fetch.MB.sec, fetch.nMsg.sec
# Uses awk only — fully compatible with BusyBox on Alpine.
# ---------------------------------------------------------------
parse_consumer_output() {
    local output="$1"
    local topic="$2"

    local partitions
    local rf
    partitions=$(echo "$topic" | sed -n 's/.*p\([0-9]*\).*/\1/p')
    rf=$(echo "$topic" | sed -n 's/.*rf\([0-9]*\).*/\1/p')

    # Get the last non-header CSV line from the output
    local result_line
    result_line=$(echo "$output" | grep -v '^start.time' | grep -v '^$' | tail -1)

    if [ -z "$result_line" ]; then
        print_error "Could not parse consumer output for $topic"
        return 1
    fi

    echo "$result_line" | awk \
        -v topic="$topic" \
        -v partitions="$partitions" \
        -v rf="$rf" \
        -v num_messages="$NUM_MESSAGES" \
        -v timestamp="$TIMESTAMP" \
        -v result_file="$RESULT_FILE" \
        -F',' '
    {
        # Trim whitespace from each field
        for (i = 1; i <= NF; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i) }

        data_mb   = $3
        tp_mb     = $4
        msg_total = $5
        msg_sec   = $6
        rebal     = $7
        fetch_t   = $8
        fetch_mb  = $9
        fetch_msg = $10

        # Append CSV row
        print timestamp "," topic "," partitions "," rf "," num_messages "," \
              data_mb "," tp_mb "," msg_total "," msg_sec "," \
              rebal "," fetch_t "," fetch_mb "," fetch_msg \
              >> result_file

        # Human-readable display
        print "Topic: "            topic
        print "Data Consumed: "    data_mb   " MB"
        print "Throughput: "       tp_mb     " MB/sec"
        print "Messages: "         msg_total
        print "Messages/sec: "     msg_sec
        print "Rebalance Time: "   rebal     " ms"
        print "Fetch Time: "       fetch_t   " ms"
        print "Fetch Throughput: " fetch_mb  " MB/sec"
    }
    '
}

# ---------------------------------------------------------------
# Run consumer test for one topic
# ---------------------------------------------------------------
run_consumer_test() {
    local topic="$1"
    local kafka_bin="$2"

    print_info "Testing topic: $topic"

    local raw_output_file="${RAW_DIR}/consumer_${topic}_${TIMESTAMP}.log"
    local group_id="benchmark-consumer-${topic}-${TIMESTAMP}"
    local output=""

    # --bootstrap-server is always required as a CLI flag.
    # Prefer bootstrap.servers from CLIENT_CONFIG if present, else fall back to env var.
    local effective_servers="$BOOTSTRAP_SERVERS"
    if [ -n "$CLIENT_CONFIG" ] && [ -f "$CLIENT_CONFIG" ]; then
        local cfg_bs
        cfg_bs=$(grep -E '^bootstrap\.servers' "$CLIENT_CONFIG" | head -1 | sed 's/.*=[ ]*//')
        [ -n "$cfg_bs" ] && effective_servers="$cfg_bs"
    fi

    if [ -n "$CLIENT_CONFIG" ] && [ -f "$CLIENT_CONFIG" ]; then
        print_info "Using consumer config: $CLIENT_CONFIG"
        print_info "Bootstrap servers: $effective_servers"
        output=$("$kafka_bin/kafka-consumer-perf-test.sh" \
            --bootstrap-server "$effective_servers" \
            --topic "$topic" \
            --messages "$NUM_MESSAGES" \
            --group "$group_id" \
            --timeout 60000 \
            --consumer.config "$CLIENT_CONFIG" \
            --show-detailed-stats 2>&1 | tee "$raw_output_file")
    else
        output=$("$kafka_bin/kafka-consumer-perf-test.sh" \
            --bootstrap-server "$BOOTSTRAP_SERVERS" \
            --topic "$topic" \
            --messages "$NUM_MESSAGES" \
            --group "$group_id" \
            --timeout 60000 \
            --show-detailed-stats 2>&1 | tee "$raw_output_file")
    fi

    # Abort early if Kafka itself reported an error
    if echo "$output" | grep -q "Exception\|ERROR\|Error"; then
        print_error "Kafka error for topic $topic — see raw log: $raw_output_file"
        echo "$output" | grep -E "Exception|ERROR|Error" | head -5
        return 1
    fi

    printf "\n"
    parse_consumer_output "$output" "$topic"
    printf "\n"
}

# ---------------------------------------------------------------
# Generate text + HTML report
# ---------------------------------------------------------------
generate_report() {
    local report_file="${RESULTS_DIR}/consumer_report_${TIMESTAMP}.txt"
    local html_report="${RESULTS_DIR}/consumer_report_${TIMESTAMP}.html"

    print_header "Generating Comparison Report"

    {
        printf "KAFKA CONSUMER BENCHMARK RESULTS\n"
        printf "=================================\n"
        printf "Timestamp: %s\n" "$TIMESTAMP"
        printf "Messages per Test: %s\n" "$NUM_MESSAGES"
        printf "\nRESULTS SUMMARY\n"
        printf "===============\n\n"

        tail -n +2 "$RESULT_FILE" | while IFS=',' read -r ts topic part rf num_msg data_mb throughput msg_consumed msg_sec rebal fetch fetch_mb fetch_msg; do
            printf "Topic: %s (Partitions: %s, RF: %s)\n" "$topic" "$part" "$rf"
            printf "  Throughput:    %s MB/sec\n" "$throughput"
            printf "  Messages/sec:  %s\n" "$msg_sec"
            printf "  Data Consumed: %s MB\n" "$data_mb"
            printf "  Fetch Time:    %s ms\n\n" "$fetch"
        done

        printf "PERFORMANCE RANKING (by Throughput)\n"
        printf "====================================\n"
        tail -n +2 "$RESULT_FILE" | sort -t',' -k7 -rn | while IFS=',' read -r ts topic part rf num_msg data_mb throughput msg_consumed msg_sec rebal fetch fetch_mb fetch_msg; do
            printf "  %s: %s MB/sec\n" "$topic" "$throughput"
        done

        printf "\nHIGHEST MESSAGE RATE\n"
        printf "====================\n"
        tail -n +2 "$RESULT_FILE" | sort -t',' -k9 -rn | while IFS=',' read -r ts topic part rf num_msg data_mb throughput msg_consumed msg_sec rebal fetch fetch_mb fetch_msg; do
            printf "  %s: %s messages/sec\n" "$topic" "$msg_sec"
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
    <title>Kafka Consumer Benchmark Results</title>
    <script src="https://cdn.plot.ly/plotly-2.27.0.min.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .header { background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%); color: white; padding: 30px; border-radius: 10px; margin-bottom: 30px; }
        .header h1 { margin: 0 0 10px 0; }
        .container { max-width: 1400px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .summary-card { background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%); color: white; padding: 20px; border-radius: 8px; }
        .summary-card h3 { margin: 0 0 8px 0; font-size: 13px; opacity: .85; }
        .summary-card .value { font-size: 26px; font-weight: bold; }
        .summary-card .label { font-size: 11px; opacity: .75; margin-top: 4px; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background: #f093fb; color: white; padding: 12px; text-align: left; }
        td { padding: 12px; border-bottom: 1px solid #ddd; }
        tr:hover { background: #f5f5f5; }
        .chart { margin: 30px 0; padding: 10px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .best { color: #28a745; font-weight: bold; }
    </style>
</head>
<body>
    <div class="header">
        <h1>📥 Kafka Consumer Benchmark Results</h1>
        <p>kafka-consumer-perf-test.sh — Performance Analysis</p>
    </div>
    <div class="container">
        <div id="summary" class="summary"></div>
        <h2>📊 Detailed Results</h2>
        <table>
            <thead>
                <tr><th>Topic</th><th>Partitions</th><th>RF</th><th>Throughput (MB/s)</th><th>Messages/sec</th><th>Data (MB)</th><th>Fetch Time (ms)</th></tr>
            </thead>
            <tbody id="resultsBody"></tbody>
        </table>
        <div class="chart" id="throughputChart"></div>
        <div class="chart" id="messagesChart"></div>
        <div class="chart" id="fetchTimeChart"></div>
        <div class="chart" id="comparisonChart"></div>
    </div>
    <script>
CSV_DATA_PLACEHOLDER

        function parseCSV() {
            const lines = csvData.trim().split('\n');
            return lines.slice(1).map(line => {
                const v = line.split(',');
                return {
                    topic:              v[1],
                    partitions:         parseInt(v[2]),
                    rf:                 parseInt(v[3]),
                    num_messages:       parseInt(v[4]),
                    data_consumed_mb:   parseFloat(v[5]),
                    throughput_mb_sec:  parseFloat(v[6]),
                    messages_consumed:  parseFloat(v[7]),
                    messages_per_sec:   parseFloat(v[8]),
                    rebalance_time_ms:  parseFloat(v[9]),
                    fetch_time_ms:      parseFloat(v[10]),
                    fetch_mb_sec:       parseFloat(v[11]),
                    fetch_msg_sec:      parseFloat(v[12])
                };
            });
        }

        function render() {
            const data = parseCSV();
            if (!data.length) return;

            const maxTP    = Math.max(...data.map(d => d.throughput_mb_sec));
            const minFetch = Math.min(...data.map(d => d.fetch_time_ms));
            const avgTP    = (data.reduce((s,d) => s + d.throughput_mb_sec, 0) / data.length).toFixed(2);
            const bestTopic = data.find(d => d.throughput_mb_sec === maxTP).topic;
            const totalMsg = data.reduce((s,d) => s + d.messages_consumed, 0);

            document.getElementById('summary').innerHTML = `
                <div class="summary-card"><h3>Topics Tested</h3><div class="value">${data.length}</div></div>
                <div class="summary-card"><h3>Total Messages Consumed</h3><div class="value">${Math.round(totalMsg).toLocaleString()}</div></div>
                <div class="summary-card"><h3>Average Throughput</h3><div class="value">${avgTP}</div><div class="label">MB/sec</div></div>
                <div class="summary-card"><h3>Peak Throughput</h3><div class="value">${maxTP.toFixed(2)}</div><div class="label">MB/sec — ${bestTopic}</div></div>
            `;

            const tbody = document.getElementById('resultsBody');
            data.forEach(row => {
                const tr = document.createElement('tr');
                tr.innerHTML = `
                    <td>${row.topic}</td>
                    <td>${row.partitions}</td>
                    <td>${row.rf}</td>
                    <td class="${row.throughput_mb_sec===maxTP?'best':''}">${row.throughput_mb_sec.toFixed(2)}</td>
                    <td>${row.messages_per_sec.toFixed(0)}</td>
                    <td>${row.data_consumed_mb.toFixed(2)}</td>
                    <td class="${row.fetch_time_ms===minFetch?'best':''}">${row.fetch_time_ms.toFixed(2)}</td>
                `;
                tbody.appendChild(tr);
            });

            // Throughput bar chart
            Plotly.newPlot('throughputChart', [{
                x: data.map(d => d.topic), y: data.map(d => d.throughput_mb_sec),
                type: 'bar', marker: { color: data.map(d => d.throughput_mb_sec), colorscale: 'Sunset' },
                text: data.map(d => d.throughput_mb_sec.toFixed(2) + ' MB/s'), textposition: 'outside'
            }], { title: 'Consumer Throughput (MB/sec)', xaxis:{title:'Topic'}, yaxis:{title:'MB/sec'}, height:400 });

            // Messages/sec bar chart
            Plotly.newPlot('messagesChart', [{
                x: data.map(d => d.topic), y: data.map(d => d.messages_per_sec),
                type: 'bar', marker: { color: '#f5576c' },
                text: data.map(d => Math.round(d.messages_per_sec).toLocaleString()), textposition: 'outside'
            }], { title: 'Messages per Second', xaxis:{title:'Topic'}, yaxis:{title:'Messages/sec'}, height:400 });

            // Fetch time bar chart
            Plotly.newPlot('fetchTimeChart', [{
                x: data.map(d => d.topic), y: data.map(d => d.fetch_time_ms),
                type: 'bar', marker: { color: '#f093fb' },
                text: data.map(d => d.fetch_time_ms.toFixed(0) + ' ms'), textposition: 'outside'
            }], { title: 'Fetch Time (ms)', xaxis:{title:'Topic'}, yaxis:{title:'ms'}, height:400 });

            // Throughput vs Fetch Time dual-axis
            Plotly.newPlot('comparisonChart', [
                { x: data.map(d=>d.topic), y: data.map(d=>d.throughput_mb_sec),
                  name:'Throughput (MB/s)', type:'scatter', mode:'lines+markers',
                  marker:{size:10, color:'#f093fb'}, yaxis:'y' },
                { x: data.map(d=>d.topic), y: data.map(d=>d.fetch_time_ms),
                  name:'Fetch Time (ms)', type:'scatter', mode:'lines+markers',
                  marker:{size:10, color:'#f5576c'}, yaxis:'y2' }
            ], {
                title: 'Throughput vs Fetch Time',
                xaxis: { title:'Topic' },
                yaxis:  { title:'Throughput (MB/sec)', side:'left' },
                yaxis2: { title:'Fetch Time (ms)', overlaying:'y', side:'right' },
                height: 400
            });
        }

        window.addEventListener('DOMContentLoaded', render);
    </script>
</body>
</html>
HTMLEOF

    # Embed CSV data inline — wrap in const csvData = `...`;
    # The placeholder token is replaced by awk with the full JS variable declaration.
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
    print_header "Kafka Consumer Native Benchmark Runner"

    print_info "Locating Kafka binaries..."
    KAFKA_BIN=$(find_kafka_bin) || {
        print_error "Could not find Kafka binaries. Set KAFKA_BIN=/path/to/kafka/bin"
        exit 1
    }
    print_info "Using Kafka binaries: $KAFKA_BIN"

    init_results_dir
    print_info "Results directory: $RESULTS_DIR"

    if [ -n "$CLIENT_CONFIG" ] && [ -f "$CLIENT_CONFIG" ]; then
        print_info "Using config file: $CLIENT_CONFIG"
    else
        print_info "Bootstrap servers: $BOOTSTRAP_SERVERS"
    fi
    print_info "Messages per test: $NUM_MESSAGES"
    printf "\n"

    print_warning "Make sure topics have data! Run producer benchmark first if needed."
    printf "\n"

    # Connectivity check — exits with a clear message if brokers unreachable
    check_connectivity
    printf "\n"

    print_header "Running Consumer Benchmark Tests"
    for topic in $TOPICS; do
        [ -z "$topic" ] && continue
        run_consumer_test "$topic" "$KAFKA_BIN" || print_warning "Skipping $topic due to error above"
        sleep 2
    done

    generate_report

    print_header "Consumer Benchmark Complete!"
    print_info "Open the HTML report:"
    printf "\n  open %s/consumer_report_%s.html\n\n" "$RESULTS_DIR" "$TIMESTAMP"
}

main "$@"
