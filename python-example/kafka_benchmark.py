#!/usr/bin/env python3
"""
Kafka Benchmark Testing Script with HTML Report Generation

This script automates Kafka performance testing (producer and consumer) 
and generates an interactive HTML report with charts.
"""

import subprocess
import re
import json
import time
from datetime import datetime
from pathlib import Path
import argparse
from typing import Dict, List, Any

try:
    import pandas as pd
    import plotly.graph_objects as go
    from plotly.subplots import make_subplots
except ImportError:
    print("Error: Required libraries not found.")
    print("Please install them using:")
    print("  pip install pandas plotly")
    exit(1)


class KafkaBenchmark:
    """Handles Kafka benchmark testing and result collection"""
    
    def __init__(self, bootstrap_servers: str, kafka_bin_path: str = ""):
        self.bootstrap_servers = bootstrap_servers
        self.kafka_bin_path = kafka_bin_path
        self.results = []
        
    def _get_command_path(self, command: str) -> str:
        """Get full path to Kafka command"""
        if self.kafka_bin_path:
            return str(Path(self.kafka_bin_path) / command)
        return command
    
    def run_producer_test(
        self,
        topic: str,
        num_records: int = 1000000,
        record_size: int = 1024,
        acks: str = "1",
        test_name: str = None
    ) -> Dict[str, Any]:
        """Run Kafka producer performance test"""
        
        test_name = test_name or f"{topic}-producer"
        
        print(f"\n{'='*70}")
        print(f"Running PRODUCER test: {test_name}")
        print(f"  Topic: {topic}")
        print(f"  Records: {num_records:,}")
        print(f"  Record size: {record_size} bytes")
        print(f"  ACKs: {acks}")
        print(f"{'='*70}")
        
        cmd = [
            self._get_command_path("kafka-producer-perf-test.sh"),
            "--topic", topic,
            "--num-records", str(num_records),
            "--record-size", str(record_size),
            "--throughput", "-1",
            "--producer-props",
            f"bootstrap.servers={self.bootstrap_servers}",
            f"acks={acks}"
        ]
        
        start_time = time.time()
        
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=300
            )
            
            elapsed_time = time.time() - start_time
            
            if result.returncode == 0:
                metrics = self._parse_producer_output(result.stdout)
                metrics.update({
                    "test_name": test_name,
                    "test_type": "producer",
                    "topic": topic,
                    "num_records": num_records,
                    "record_size": record_size,
                    "acks": acks,
                    "status": "success",
                    "elapsed_time": elapsed_time,
                    "timestamp": datetime.now().isoformat()
                })
                
                print(f"✓ Test completed successfully")
                print(f"  Throughput: {metrics.get('throughput_mb_sec', 0):.2f} MB/sec")
                print(f"  Records/sec: {metrics.get('records_per_sec', 0):.2f}")
                print(f"  Avg Latency: {metrics.get('avg_latency_ms', 0):.2f} ms")
                
                self.results.append(metrics)
                return metrics
            else:
                print(f"✗ Test failed: {result.stderr}")
                error_result = {
                    "test_name": test_name,
                    "test_type": "producer",
                    "topic": topic,
                    "status": "failed",
                    "error": result.stderr,
                    "timestamp": datetime.now().isoformat()
                }
                self.results.append(error_result)
                return error_result
                
        except subprocess.TimeoutExpired:
            print(f"✗ Test timed out after 5 minutes")
            return {"test_name": test_name, "test_type": "producer", "status": "timeout"}
        except Exception as e:
            print(f"✗ Test error: {str(e)}")
            return {"test_name": test_name, "test_type": "producer", "status": "error", "error": str(e)}
    
    def _parse_producer_output(self, output: str) -> Dict[str, float]:
        """Parse kafka-producer-perf-test.sh output"""
        metrics = {}
        
        # Example: 1000000 records sent, 199960.007999 records/sec (195.27 MB/sec), 2.41 ms avg latency, 445.00 ms max latency
        pattern = r'(\d+)\s+records sent,\s+([\d.]+)\s+records/sec\s+\(([\d.]+)\s+MB/sec\),\s+([\d.]+)\s+ms avg latency,\s+([\d.]+)\s+ms max latency'
        match = re.search(pattern, output)
        
        if match:
            metrics['records_sent'] = float(match.group(1))
            metrics['records_per_sec'] = float(match.group(2))
            metrics['throughput_mb_sec'] = float(match.group(3))
            metrics['avg_latency_ms'] = float(match.group(4))
            metrics['max_latency_ms'] = float(match.group(5))
        
        return metrics
    
    def run_consumer_test(
        self,
        topic: str,
        messages: int = 1000000,
        test_name: str = None
    ) -> Dict[str, Any]:
        """Run Kafka consumer performance test"""
        
        test_name = test_name or f"{topic}-consumer"
        
        print(f"\n{'='*70}")
        print(f"Running CONSUMER test: {test_name}")
        print(f"  Topic: {topic}")
        print(f"  Messages: {messages:,}")
        print(f"{'='*70}")
        
        # Use first bootstrap server for consumer
        bootstrap_server = self.bootstrap_servers.split(',')[0]
        
        cmd = [
            self._get_command_path("kafka-consumer-perf-test.sh"),
            "--bootstrap-server", bootstrap_server,
            "--topic", topic,
            "--messages", str(messages),
            "--show-detailed-stats"
        ]
        
        start_time = time.time()
        
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=300
            )
            
            elapsed_time = time.time() - start_time
            
            if result.returncode == 0:
                metrics = self._parse_consumer_output(result.stdout)
                metrics.update({
                    "test_name": test_name,
                    "test_type": "consumer",
                    "topic": topic,
                    "messages": messages,
                    "status": "success",
                    "elapsed_time": elapsed_time,
                    "timestamp": datetime.now().isoformat()
                })
                
                print(f"✓ Test completed successfully")
                print(f"  Throughput: {metrics.get('throughput_mb_sec', 0):.2f} MB/sec")
                print(f"  Records/sec: {metrics.get('records_per_sec', 0):.2f}")
                
                self.results.append(metrics)
                return metrics
            else:
                print(f"✗ Test failed: {result.stderr}")
                error_result = {
                    "test_name": test_name,
                    "test_type": "consumer",
                    "topic": topic,
                    "status": "failed",
                    "error": result.stderr,
                    "timestamp": datetime.now().isoformat()
                }
                self.results.append(error_result)
                return error_result
                
        except subprocess.TimeoutExpired:
            print(f"✗ Test timed out after 5 minutes")
            return {"test_name": test_name, "test_type": "consumer", "status": "timeout"}
        except Exception as e:
            print(f"✗ Test error: {str(e)}")
            return {"test_name": test_name, "test_type": "consumer", "status": "error", "error": str(e)}
    
    def _parse_consumer_output(self, output: str) -> Dict[str, float]:
        """Parse kafka-consumer-perf-test.sh output"""
        metrics = {}
        
        # The output is CSV-like with headers and data
        # start.time, end.time, data.consumed.in.MB, MB.sec, data.consumed.in.nMsg, nMsg.sec, rebalance.time.ms, fetch.time.ms, fetch.MB.sec, fetch.nMsg.sec
        
        lines = output.strip().split('\n')
        for line in reversed(lines):
            if line.strip() and not line.startswith('start.time'):
                parts = [p.strip() for p in line.split(',')]
                if len(parts) >= 6:
                    try:
                        metrics['data_consumed_mb'] = float(parts[2])
                        metrics['throughput_mb_sec'] = float(parts[3])
                        metrics['messages_consumed'] = float(parts[4])
                        metrics['records_per_sec'] = float(parts[5])
                        if len(parts) >= 10:
                            metrics['rebalance_time_ms'] = float(parts[6])
                            metrics['fetch_time_ms'] = float(parts[7])
                    except (ValueError, IndexError):
                        pass
                break
        
        return metrics
    
    def run_test_suite(self, producer_configs: List[Dict[str, Any]], consumer_configs: List[Dict[str, Any]] = None):
        """Run a suite of benchmark tests"""
        print(f"\n{'#'*70}")
        print(f"# Kafka Benchmark Test Suite")
        print(f"# Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"# Bootstrap servers: {self.bootstrap_servers}")
        print(f"{'#'*70}")
        
        # Run producer tests
        if producer_configs:
            print(f"\n{'='*70}")
            print(f"PRODUCER TESTS ({len(producer_configs)} tests)")
            print(f"{'='*70}")
            for config in producer_configs:
                self.run_producer_test(**config)
                time.sleep(2)
        
        # Run consumer tests
        if consumer_configs:
            print(f"\n{'='*70}")
            print(f"CONSUMER TESTS ({len(consumer_configs)} tests)")
            print(f"{'='*70}")
            for config in consumer_configs:
                self.run_consumer_test(**config)
                time.sleep(2)
        
        print(f"\n{'#'*70}")
        print(f"# Test Suite Completed")
        print(f"# Total tests: {len(self.results)}")
        print(f"# Successful: {sum(1 for r in self.results if r.get('status') == 'success')}")
        print(f"{'#'*70}\n")
    
    def save_results(self, output_file: str = "benchmark_results.json"):
        """Save results to JSON file"""
        output_path = Path(output_file)
        with open(output_path, 'w') as f:
            json.dump(self.results, f, indent=2)
        print(f"Results saved to: {output_path.absolute()}")
        return output_path


class ReportGenerator:
    """Generates HTML reports with interactive charts"""
    
    def __init__(self, results: List[Dict[str, Any]]):
        self.results = results
        successful_results = [r for r in results if r.get('status') == 'success']
        self.df = pd.DataFrame(successful_results) if successful_results else pd.DataFrame()
        
        if not self.df.empty:
            self.producer_df = self.df[self.df['test_type'] == 'producer']
            self.consumer_df = self.df[self.df['test_type'] == 'consumer']
        else:
            self.producer_df = pd.DataFrame()
            self.consumer_df = pd.DataFrame()
    
    def generate_html_report(self, output_file: str = "benchmark_report.html"):
        """Generate comprehensive HTML report with charts"""
        
        if self.df.empty:
            print("No successful test results to generate report")
            return None
        
        # Create charts
        fig = self._create_charts()
        
        # Generate summary
        summary_html = self._generate_summary_html()
        
        # Complete HTML
        full_html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>Kafka Benchmark Report</title>
            <meta charset="utf-8">
            <style>
                body {{
                    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                    margin: 0;
                    padding: 20px;
                    background-color: #f5f5f5;
                }}
                .container {{
                    max-width: 1400px;
                    margin: 0 auto;
                    background: white;
                    padding: 30px;
                    border-radius: 10px;
                    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                }}
                h1 {{
                    color: #333;
                    border-bottom: 3px solid #007acc;
                    padding-bottom: 10px;
                }}
                .summary {{
                    background: #f8f9fa;
                    padding: 20px;
                    border-radius: 8px;
                    margin: 20px 0;
                }}
                .summary h2 {{
                    color: #007acc;
                    margin-top: 0;
                }}
                table {{
                    width: 100%;
                    border-collapse: collapse;
                    margin: 20px 0;
                }}
                th, td {{
                    padding: 12px;
                    text-align: left;
                    border-bottom: 1px solid #ddd;
                }}
                th {{
                    background-color: #007acc;
                    color: white;
                    font-weight: 600;
                }}
                tr:hover {{
                    background-color: #f5f5f5;
                }}
                .metric {{
                    display: inline-block;
                    margin: 10px 20px 10px 0;
                }}
                .metric-label {{
                    color: #666;
                    font-size: 0.9em;
                }}
                .metric-value {{
                    font-size: 1.5em;
                    font-weight: bold;
                    color: #007acc;
                }}
                .footer {{
                    margin-top: 30px;
                    padding-top: 20px;
                    border-top: 1px solid #ddd;
                    text-align: center;
                    color: #666;
                }}
            </style>
        </head>
        <body>
            <div class="container">
                <h1>🚀 Kafka Performance Benchmark Report</h1>
                {summary_html}
                <div id="charts">
                    {fig.to_html(include_plotlyjs='cdn', div_id='charts')}
                </div>
                <div class="footer">
                    <p>Generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
                </div>
            </div>
        </body>
        </html>
        """
        
        output_path = Path(output_file)
        with open(output_path, 'w') as f:
            f.write(full_html)
        
        print(f"\n✓ HTML report generated: {output_path.absolute()}")
        return output_path
    
    def _create_charts(self):
        """Create all benchmark charts"""
        
        colors = {
            'p1-rf1': '#1f77b4',
            'p1-rf3': '#ff7f0e',
            'p3-rf3': '#2ca02c',
            'p12-rf3': '#d62728',
            'p30-rf3': '#9467bd'
        }
        
        has_producer = not self.producer_df.empty
        has_consumer = not self.consumer_df.empty
        
        if has_producer and has_consumer:
            # Both producer and consumer tests
            fig = make_subplots(
                rows=3, cols=2,
                subplot_titles=(
                    'Producer Throughput (MB/sec)',
                    'Producer Latency (ms)',
                    'Consumer Throughput (MB/sec)',
                    'Consumer Records/sec',
                    'Producer vs Consumer Comparison',
                    'Producer Records/sec'
                ),
                specs=[
                    [{"type": "bar"}, {"type": "bar"}],
                    [{"type": "bar"}, {"type": "bar"}],
                    [{"type": "bar"}, {"type": "bar"}]
                ],
                vertical_spacing=0.12,
                horizontal_spacing=0.12
            )
            
            # Producer throughput
            fig.add_trace(
                go.Bar(
                    x=self.producer_df['test_name'],
                    y=self.producer_df['throughput_mb_sec'],
                    name='Producer',
                    marker_color=[colors.get(t, '#1f77b4') for t in self.producer_df['topic']],
                    text=self.producer_df['throughput_mb_sec'].round(2),
                    textposition='outside'
                ),
                row=1, col=1
            )
            
            # Producer latency
            if 'avg_latency_ms' in self.producer_df.columns:
                fig.add_trace(
                    go.Bar(
                        x=self.producer_df['test_name'],
                        y=self.producer_df['avg_latency_ms'],
                        name='Avg Latency',
                        marker_color=[colors.get(t, '#1f77b4') for t in self.producer_df['topic']],
                        text=self.producer_df['avg_latency_ms'].round(2),
                        textposition='outside'
                    ),
                    row=1, col=2
                )
            
            # Consumer throughput
            fig.add_trace(
                go.Bar(
                    x=self.consumer_df['test_name'],
                    y=self.consumer_df['throughput_mb_sec'],
                    name='Consumer',
                    marker_color=[colors.get(t, '#2ca02c') for t in self.consumer_df['topic']],
                    text=self.consumer_df['throughput_mb_sec'].round(2),
                    textposition='outside'
                ),
                row=2, col=1
            )
            
            # Consumer records/sec
            fig.add_trace(
                go.Bar(
                    x=self.consumer_df['test_name'],
                    y=self.consumer_df['records_per_sec'],
                    name='Consumer Recs/sec',
                    marker_color=[colors.get(t, '#2ca02c') for t in self.consumer_df['topic']],
                    text=self.consumer_df['records_per_sec'].round(0),
                    textposition='outside'
                ),
                row=2, col=2
            )
            
            # Producer vs Consumer comparison by topic
            topics = list(set(self.producer_df['topic'].unique()) & set(self.consumer_df['topic'].unique()))
            prod_throughput = [self.producer_df[self.producer_df['topic'] == t]['throughput_mb_sec'].mean() for t in topics]
            cons_throughput = [self.consumer_df[self.consumer_df['topic'] == t]['throughput_mb_sec'].mean() for t in topics]
            
            fig.add_trace(
                go.Bar(
                    x=topics,
                    y=prod_throughput,
                    name='Producer',
                    marker_color='#1f77b4'
                ),
                row=3, col=1
            )
            fig.add_trace(
                go.Bar(
                    x=topics,
                    y=cons_throughput,
                    name='Consumer',
                    marker_color='#2ca02c'
                ),
                row=3, col=1
            )
            
            # Producer records/sec
            fig.add_trace(
                go.Bar(
                    x=self.producer_df['test_name'],
                    y=self.producer_df['records_per_sec'],
                    name='Producer Recs/sec',
                    marker_color=[colors.get(t, '#1f77b4') for t in self.producer_df['topic']],
                    text=self.producer_df['records_per_sec'].round(0),
                    textposition='outside'
                ),
                row=3, col=2
            )
            
            fig.update_layout(
                title_text=f"Kafka Benchmark Results - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
                showlegend=True,
                height=1400,
                template='plotly_white'
            )
            
        else:
            # Producer-only tests
            df_to_use = self.producer_df if has_producer else self.consumer_df
            
            fig = make_subplots(
                rows=3, cols=2,
                subplot_titles=(
                    'Throughput (MB/sec)',
                    'Records Per Second',
                    'Average Latency (ms)' if has_producer else 'Data Consumed (MB)',
                    'Max Latency (ms)' if has_producer else 'Fetch Time (ms)',
                    'Throughput vs Latency' if has_producer else 'Performance Overview',
                    'Total Data Volume (MB)'
                ),
                specs=[
                    [{"type": "bar"}, {"type": "bar"}],
                    [{"type": "bar"}, {"type": "bar"}],
                    [{"type": "scatter"} if has_producer else {"type": "bar"}, {"type": "bar"}]
                ],
                vertical_spacing=0.12,
                horizontal_spacing=0.12
            )
            
            # Throughput
            fig.add_trace(
                go.Bar(
                    x=df_to_use['test_name'],
                    y=df_to_use['throughput_mb_sec'],
                    marker_color=[colors.get(t, '#8c564b') for t in df_to_use['topic']],
                    text=df_to_use['throughput_mb_sec'].round(2),
                    textposition='outside'
                ),
                row=1, col=1
            )
            
            # Records/sec
            fig.add_trace(
                go.Bar(
                    x=df_to_use['test_name'],
                    y=df_to_use['records_per_sec'],
                    marker_color=[colors.get(t, '#8c564b') for t in df_to_use['topic']],
                    text=df_to_use['records_per_sec'].round(0),
                    textposition='outside'
                ),
                row=1, col=2
            )
            
            # Row 2
            if has_producer and 'avg_latency_ms' in df_to_use.columns:
                fig.add_trace(
                    go.Bar(
                        x=df_to_use['test_name'],
                        y=df_to_use['avg_latency_ms'],
                        marker_color=[colors.get(t, '#8c564b') for t in df_to_use['topic']],
                        text=df_to_use['avg_latency_ms'].round(2),
                        textposition='outside'
                    ),
                    row=2, col=1
                )
                
                fig.add_trace(
                    go.Bar(
                        x=df_to_use['test_name'],
                        y=df_to_use['max_latency_ms'],
                        marker_color=[colors.get(t, '#8c564b') for t in df_to_use['topic']],
                        text=df_to_use['max_latency_ms'].round(2),
                        textposition='outside'
                    ),
                    row=2, col=2
                )
            
            fig.update_layout(
                title_text=f"Kafka Benchmark Results - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
                showlegend=False,
                height=1400,
                template='plotly_white'
            )
        
        fig.update_xaxes(tickangle=-45)
        
        return fig
    
    def _generate_summary_html(self) -> str:
        """Generate summary statistics HTML"""
        
        has_producer = not self.producer_df.empty
        has_consumer = not self.consumer_df.empty
        
        # Overall statistics
        if has_producer:
            total_records = self.producer_df['records_sent'].sum() if 'records_sent' in self.producer_df.columns else 0
            avg_throughput = self.producer_df['throughput_mb_sec'].mean()
            max_throughput = self.producer_df['throughput_mb_sec'].max()
            best_test = self.producer_df.loc[self.producer_df['throughput_mb_sec'].idxmax(), 'test_name']
        else:
            total_records = self.consumer_df['messages_consumed'].sum() if 'messages_consumed' in self.consumer_df.columns else 0
            avg_throughput = self.consumer_df['throughput_mb_sec'].mean()
            max_throughput = self.consumer_df['throughput_mb_sec'].max()
            best_test = self.consumer_df.loc[self.consumer_df['throughput_mb_sec'].idxmax(), 'test_name']
        
        # Topic order
        topic_order = ['p1-rf1', 'p1-rf3', 'p3-rf3', 'p12-rf3', 'p30-rf3']
        
        # Build summary tables
        summary_tables = ""
        
        if has_producer:
            producer_stats = self.producer_df.groupby('topic').agg({
                'throughput_mb_sec': 'mean',
                'records_per_sec': 'mean'
            }).round(2)
            if 'avg_latency_ms' in self.producer_df.columns:
                producer_stats['avg_latency_ms'] = self.producer_df.groupby('topic')['avg_latency_ms'].mean().round(2)
            
            producer_stats = producer_stats.reindex([t for t in topic_order if t in producer_stats.index])
            
            rows = ""
            for topic, row in producer_stats.iterrows():
                latency_col = f"<td>{row['avg_latency_ms']:.2f}</td>" if 'avg_latency_ms' in row else ""
                rows += f"""
                <tr>
                    <td><strong>{topic}</strong></td>
                    <td>{row['throughput_mb_sec']:.2f}</td>
                    <td>{row['records_per_sec']:.2f}</td>
                    {latency_col}
                </tr>
                """
            
            latency_header = "<th>Avg Latency (ms)</th>" if 'avg_latency_ms' in self.producer_df.columns else ""
            summary_tables += f"""
            <h3>Producer Performance by Topic</h3>
            <table>
                <thead>
                    <tr>
                        <th>Topic</th>
                        <th>Avg Throughput (MB/sec)</th>
                        <th>Avg Records/sec</th>
                        {latency_header}
                    </tr>
                </thead>
                <tbody>
                    {rows}
                </tbody>
            </table>
            """
        
        if has_consumer:
            consumer_stats = self.consumer_df.groupby('topic').agg({
                'throughput_mb_sec': 'mean',
                'records_per_sec': 'mean'
            }).round(2)
            consumer_stats = consumer_stats.reindex([t for t in topic_order if t in consumer_stats.index])
            
            rows = ""
            for topic, row in consumer_stats.iterrows():
                rows += f"""
                <tr>
                    <td><strong>{topic}</strong></td>
                    <td>{row['throughput_mb_sec']:.2f}</td>
                    <td>{row['records_per_sec']:.2f}</td>
                </tr>
                """
            
            summary_tables += f"""
            <h3>Consumer Performance by Topic</h3>
            <table>
                <thead>
                    <tr>
                        <th>Topic</th>
                        <th>Avg Throughput (MB/sec)</th>
                        <th>Avg Records/sec</th>
                    </tr>
                </thead>
                <tbody>
                    {rows}
                </tbody>
            </table>
            """
        
        insights = []
        if has_producer:
            insights.append("<li><strong>Replication Impact:</strong> Compare p1-rf1 vs p1-rf3 to see replication overhead</li>")
            insights.append("<li><strong>Partition Scaling:</strong> Higher partition counts improve throughput</li>")
        if has_consumer:
            insights.append("<li><strong>Consumer Performance:</strong> Consumers typically achieve higher throughput</li>")
        if has_producer and has_consumer:
            insights.append("<li><strong>End-to-End:</strong> Compare producer and consumer for the same topic</li>")
        
        summary_html = f"""
        <div class="summary">
            <h2>📊 Summary Statistics</h2>
            <div class="metric">
                <div class="metric-label">Total Records Tested</div>
                <div class="metric-value">{total_records:,.0f}</div>
            </div>
            <div class="metric">
                <div class="metric-label">Average Throughput</div>
                <div class="metric-value">{avg_throughput:.2f} MB/sec</div>
            </div>
            <div class="metric">
                <div class="metric-label">Peak Throughput</div>
                <div class="metric-value">{max_throughput:.2f} MB/sec</div>
            </div>
            <div class="metric">
                <div class="metric-label">Best Configuration</div>
                <div class="metric-value">{best_test}</div>
            </div>
            
            {summary_tables}
            
            <h3>Key Insights</h3>
            <ul>
                {"".join(insights)}
            </ul>
        </div>
        """
        
        return summary_html


def main():
    parser = argparse.ArgumentParser(
        description='Run Kafka benchmarks and generate HTML reports'
    )
    parser.add_argument(
        '--bootstrap-servers',
        default='localhost:29092,localhost:39092,localhost:49092',
        help='Kafka bootstrap servers'
    )
    parser.add_argument(
        '--kafka-bin',
        default='',
        help='Path to Kafka bin directory (optional)'
    )
    parser.add_argument(
        '--output-dir',
        default='.',
        help='Output directory for reports'
    )
    parser.add_argument(
        '--num-records',
        type=int,
        default=1000000,
        help='Number of records per test (default: 1000000)'
    )
    parser.add_argument(
        '--record-size',
        type=int,
        default=1024,
        help='Record size in bytes (default: 1024)'
    )
    parser.add_argument(
        '--skip-consumer',
        action='store_true',
        help='Skip consumer tests (producer only)'
    )
    
    args = parser.parse_args()
    
    # Create output directory
    output_dir = Path(args.output_dir)
    output_dir.mkdir(exist_ok=True)
    
    # Initialize benchmark
    benchmark = KafkaBenchmark(
        bootstrap_servers=args.bootstrap_servers,
        kafka_bin_path=args.kafka_bin
    )
    
    # Define producer test configurations
    producer_configs = [
        {
            "topic": "p1-rf1",
            "num_records": args.num_records,
            "record_size": args.record_size,
            "acks": "1",
            "test_name": "1P-RF1 Producer"
        },
        {
            "topic": "p1-rf3",
            "num_records": args.num_records,
            "record_size": args.record_size,
            "acks": "all",
            "test_name": "1P-RF3 Producer"
        },
        {
            "topic": "p3-rf3",
            "num_records": args.num_records,
            "record_size": args.record_size,
            "acks": "all",
            "test_name": "3P-RF3 Producer"
        },
        {
            "topic": "p12-rf3",
            "num_records": args.num_records,
            "record_size": args.record_size,
            "acks": "all",
            "test_name": "12P-RF3 Producer"
        },
        {
            "topic": "p30-rf3",
            "num_records": args.num_records,
            "record_size": args.record_size,
            "acks": "all",
            "test_name": "30P-RF3 Producer"
        }
    ]
    
    # Define consumer test configurations
    consumer_configs = None if args.skip_consumer else [
        {
            "topic": "p1-rf1",
            "messages": args.num_records,
            "test_name": "1P-RF1 Consumer"
        },
        {
            "topic": "p1-rf3",
            "messages": args.num_records,
            "test_name": "1P-RF3 Consumer"
        },
        {
            "topic": "p3-rf3",
            "messages": args.num_records,
            "test_name": "3P-RF3 Consumer"
        },
        {
            "topic": "p12-rf3",
            "messages": args.num_records,
            "test_name": "12P-RF3 Consumer"
        },
        {
            "topic": "p30-rf3",
            "messages": args.num_records,
            "test_name": "30P-RF3 Consumer"
        }
    ]
    
    # Run tests
    benchmark.run_test_suite(producer_configs, consumer_configs)
    
    # Save results
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    json_file = output_dir / f"benchmark_results_{timestamp}.json"
    benchmark.save_results(str(json_file))
    
    # Generate report
    report_gen = ReportGenerator(benchmark.results)
    html_file = output_dir / f"benchmark_report_{timestamp}.html"
    report_gen.generate_html_report(str(html_file))
    
    print(f"\n{'='*70}")
    print(f"✓ Benchmark complete!")
    print(f"  Results: {json_file}")
    print(f"  Report:  {html_file}")
    print(f"{'='*70}\n")


if __name__ == "__main__":
    main()
