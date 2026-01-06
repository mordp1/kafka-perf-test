# Images Directory

This directory contains screenshots and example images for the README.

## Required Images

To complete the README, add these screenshots:

1. **producer-dashboard.png** - Full producer benchmark HTML report
   - Take a screenshot of the complete producer report showing:
   - Summary cards at the top
   - Detailed results table
   - All 4 charts (throughput, latency, records/sec, percentiles)

2. **consumer-dashboard.png** - Full consumer benchmark HTML report
   - Take a screenshot of the complete consumer report showing:
   - Summary cards
   - Results table
   - All 4 charts (throughput, messages/sec, fetch time, comparison)

3. **throughput-chart.png** - Close-up of throughput comparison chart
   - Crop just the throughput bar chart for side-by-side comparison

4. **latency-chart.png** - Close-up of latency percentiles chart
   - Crop just the latency percentiles line chart

## How to Generate Screenshots

1. Run both benchmarks:
   ```bash
   ./producer-benchmark-runner.sh
   ./consumer-benchmark-runner.sh
   ```

2. Open the generated HTML reports:
   ```bash
   open benchmark_results/report_*.html
   open benchmark_results/consumer_report_*.html
   ```

3. Take screenshots (macOS: Cmd+Shift+4, select area)

4. Save screenshots to this directory with the exact names listed above

5. Optionally optimize images:
   ```bash
   # macOS with ImageOptim
   # Or use online tools like TinyPNG
   ```

## Image Specifications

- **Format**: PNG (preferred) or JPG
- **Width**: 800-1200px for full dashboards, 400-600px for individual charts
- **Quality**: High quality, but optimized for web (< 500KB per image)
- **Background**: Keep the original white/light background

## Alternative: Use Placeholder

If you don't have screenshots yet, the README will still work. Users can generate their own reports and see the results.

You can also create placeholder images with text:
```bash
# Example with ImageMagick
convert -size 800x600 xc:lightgray \
  -pointsize 30 -draw "text 250,300 'Run benchmark to see results'" \
  producer-dashboard.png
```

## Git Tracking

These image files should be tracked in git (not in .gitignore) so they appear on GitHub.
