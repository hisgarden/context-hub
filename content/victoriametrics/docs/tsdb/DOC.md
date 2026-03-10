---
name: tsdb
description: "VictoriaMetrics open-source time series database HTTP API for metrics ingestion, querying with MetricsQL, data export, and administration."
metadata:
  languages: "http"
  versions: "1.x"
  revision: 1
  updated-on: "2026-03-09"
  source: community
  tags: "victoriametrics,tsdb,metrics,monitoring,prometheus,timeseries,metricsql,observability"
---

# VictoriaMetrics HTTP API

VictoriaMetrics is an open-source time series database optimized for monitoring and observability. It is Prometheus-compatible, supports multiple ingestion protocols, and uses MetricsQL (a PromQL superset) for querying.

## Architecture

**Single-node** (port 8428): All-in-one binary. All endpoints use `http://localhost:8428` as the base URL.

**Cluster** (three components):

- **vminsert** (port 8480): Accepts ingested data, distributes to vmstorage via consistent hashing.
- **vmselect** (port 8481): Executes queries by fetching from all vmstorage nodes.
- **vmstorage** (port 8482): Stores raw time series data (shared-nothing, nodes don't communicate).

Cluster URLs include a tenant prefix: `http://<component>:<port>/insert/<accountID>/...` for writes and `http://<component>:<port>/select/<accountID>/prometheus/...` for reads. The `accountID` is a 32-bit integer (0 is the default tenant). Tenants auto-create on first write.

**vmagent** (port 8429): Lightweight agent that scrapes targets and accepts push data, forwarding to VictoriaMetrics via remote write.

---

## Data Model

A **time series** is identified by a metric name plus a set of key-value labels:

```
requests_total{path="/", code="200"} 123 1609459200000
```

- The metric name is a special label `__name__`.
- Values are float64 (integers up to 12 decimal digits are exact).
- Timestamps are Unix milliseconds.
- The data model is schema-less -- no need to pre-define metrics or labels.

### Metric Types

VictoriaMetrics stores all types identically; types are informational only:

- **Counter**: Cumulative value that only increases (e.g., `requests_total`). Use `rate()` or `increase()` to query.
- **Gauge**: Value that goes up and down (e.g., `memory_usage_bytes`).
- **Histogram**: Distribution as bucket counters with `le` or `vmrange` labels plus `_sum` and `_count`.
- **Summary**: Pre-calculated quantiles with `quantile` labels plus `_sum` and `_count`.

---

## Data Ingestion APIs

### Prometheus Remote Write

```bash
# Single-node
curl -X POST http://localhost:8428/api/v1/write \
  --data-binary @payload.snappy \
  -H 'Content-Type: application/x-protobuf' \
  -H 'Content-Encoding: snappy'

# Cluster
curl -X POST http://<vminsert>:8480/insert/0/prometheus/api/v1/write \
  --data-binary @payload.snappy \
  -H 'Content-Type: application/x-protobuf' \
  -H 'Content-Encoding: snappy'
```

### Prometheus Exposition Format

```bash
# Single-node
curl -d 'metric_name{foo="bar"} 123' -X POST \
  http://localhost:8428/api/v1/import/prometheus

# With explicit timestamp (milliseconds)
curl -d 'metric_name{foo="bar"} 123 1609459200000' -X POST \
  'http://localhost:8428/api/v1/import/prometheus?timestamp=1609459200000'

# Cluster
curl -d 'metric_name{foo="bar"} 123' -X POST \
  http://<vminsert>:8480/insert/0/prometheus/api/v1/import/prometheus
```

Supports Pushgateway format: `/api/v1/import/prometheus/metrics/job/<job>/instance/<instance>`

Supports gzip: add `-H 'Content-Encoding: gzip'`.

### InfluxDB Line Protocol

```bash
# Single-node
curl -d 'measurement,tag1=value1,tag2=value2 field1=123,field2=1.23' \
  -X POST http://localhost:8428/write

# Cluster
curl -d 'measurement,tag1=value1,tag2=value2 field1=123,field2=1.23' \
  -X POST http://<vminsert>:8480/insert/0/influx/write
```

Each field becomes a separate time series: `measurement_field1{tag1="value1",tag2="value2"}`.

### JSON Lines Import

```bash
# Single-node
curl -H 'Content-Type: application/json' \
  --data-binary "@data.json" \
  -X POST http://localhost:8428/api/v1/import

# Cluster
curl -H 'Content-Type: application/json' \
  --data-binary "@data.json" \
  -X POST http://<vminsert>:8480/insert/0/prometheus/api/v1/import
```

JSON format (one object per line):

```json
{"metric":{"__name__":"foo","job":"bar"},"values":[1,2,3],"timestamps":[1609459200000,1609459260000,1609459320000]}
```

Optional query parameter: `extra_label=name=value` to add labels to all imported series.

### CSV Import

```bash
# Single-node
curl -X POST \
  'http://localhost:8428/api/v1/import/csv?format=2:label:job,3:label:instance,4:metric:demo,5:time:unix_s' \
  -T data.csv

# Multi-metric example
curl -d "GOOG,1.23,4.56,NYSE" \
  'http://localhost:8428/api/v1/import/csv?format=2:metric:ask,3:metric:bid,1:label:ticker,4:label:market'

# Cluster
curl -X POST \
  'http://<vminsert>:8480/insert/0/prometheus/api/v1/import/csv?format=...' \
  -T data.csv
```

Format spec: `<column_pos>:<type>:<context>` where type is `metric`, `label`, or `time`. Time formats: `unix_s`, `unix_ms`, `unix_ns`, `rfc3339`, `custom:<layout>`.

### Native Binary Import

The most efficient format for bulk transfers (pairs with native export):

```bash
# Single-node
curl -X POST http://localhost:8428/api/v1/import/native -T data.bin

# Cluster
curl -X POST http://<vminsert>:8480/insert/0/prometheus/api/v1/import/native -T data.bin
```

### DataDog API

```bash
# v1 series - Single-node
curl -X POST -H 'Content-Type: application/json' \
  --data-binary '{"series":[{"host":"myhost","interval":20,"metric":"my.metric","points":[[1609459200,3.14]],"tags":["env:prod"],"type":"rate"}]}' \
  http://localhost:8428/datadog/api/v1/series

# v2 series - Single-node
curl -X POST -H 'Content-Type: application/json' \
  --data-binary '{"series":[{"metric":"my.metric","type":0,"points":[{"timestamp":1609459200,"value":3.14}],"resources":[{"type":"host","name":"myhost"}],"tags":["env:prod"]}]}' \
  http://localhost:8428/datadog/api/v2/series

# Cluster (v1)
curl -X POST -H 'Content-Type: application/json' \
  --data-binary @data.json \
  http://<vminsert>:8480/insert/0/datadog/api/v1/series

# Cluster (v2)
curl -X POST -H 'Content-Type: application/json' \
  --data-binary @data.json \
  http://<vminsert>:8480/insert/0/datadog/api/v2/series
```

### OpenTSDB

HTTP API (requires `-opentsdbHTTPListenAddr` flag):

```bash
# Single-node
curl -H 'Content-Type: application/json' \
  -d '[{"metric":"foo","value":45.34},{"metric":"bar","value":43}]' \
  http://localhost:4242/api/put

# Cluster
curl -H 'Content-Type: application/json' \
  -d '[{"metric":"foo","value":45.34}]' \
  http://<vminsert>:4242/insert/42/opentsdb/api/put
```

Telnet protocol (requires `-opentsdbListenAddr` flag, default port 4242):

```bash
echo "put foo.bar.baz $(date +%s) 123 tag1=value1 tag2=value2" | nc -N localhost 4242
```

### Graphite Plaintext

Requires `-graphiteListenAddr` flag (default port 2003):

```bash
echo "foo.bar.baz;tag1=value1;tag2=value2 123 $(date +%s)" | nc -N localhost 2003
```

### OpenTelemetry

```bash
# Single-node
# Endpoint: http://localhost:8428/opentelemetry/v1/metrics

# Cluster
# Endpoint: http://<vminsert>:8480/insert/0/opentelemetry/v1/metrics
```

Configure the OpenTelemetry Collector to send OTLP metrics to the above endpoints.

---

## Query APIs

### Instant Query

Returns one data point per series at a specific timestamp.

```bash
# Single-node
curl 'http://localhost:8428/prometheus/api/v1/query' \
  -d 'query=vm_http_request_errors_total'

# With timestamp and step
curl 'http://localhost:8428/prometheus/api/v1/query' \
  -d 'query=rate(requests_total[5m])' \
  -d 'time=2024-01-01T00:00:00Z' \
  -d 'step=5m'

# Cluster
curl 'http://<vmselect>:8481/select/0/prometheus/api/v1/query' \
  -d 'query=vm_http_request_errors_total'
```

**Parameters:**

| Parameter | Description |
|-----------|-------------|
| `query` | MetricsQL expression (required) |
| `time` | Evaluation timestamp. Unix seconds/ms, RFC3339, or relative (e.g., `-5m`). Default: now |
| `step` | Lookbehind window for finding data when exact timestamp has no sample. Default: `5m` |
| `timeout` | Query timeout override |
| `extra_label` | Additional label filter: `name=value` |
| `extra_filters[]` | Additional series selectors |
| `round_digits` | Round values to N decimal places |

**Response:**

```json
{
  "status": "success",
  "data": {
    "resultType": "vector",
    "result": [
      {
        "metric": {"__name__": "up", "job": "prometheus"},
        "value": [1609459200, "1"]
      }
    ]
  },
  "stats": {
    "executionTimeMsec": 5,
    "seriesFetched": 1
  }
}
```

### Range Query

Returns multiple data points per series across a time range.

```bash
# Single-node
curl 'http://localhost:8428/prometheus/api/v1/query_range' \
  -d 'query=sum(increase(vm_http_request_errors_total{job="foo"}[5m]))' \
  -d 'start=-1d' \
  -d 'step=1h'

# With explicit start and end
curl 'http://localhost:8428/prometheus/api/v1/query_range' \
  -d 'query=rate(requests_total[5m])' \
  -d 'start=2024-01-01T00:00:00Z' \
  -d 'end=2024-01-02T00:00:00Z' \
  -d 'step=15m'

# Cluster
curl 'http://<vmselect>:8481/select/0/prometheus/api/v1/query_range' \
  -d 'query=...' -d 'start=-1d' -d 'step=1h'
```

**Parameters:**

| Parameter | Description |
|-----------|-------------|
| `query` | MetricsQL expression (required) |
| `start` | Range start. Unix seconds/ms, RFC3339, or relative (e.g., `-1d`). Default: current time |
| `end` | Range end. Default: current time |
| `step` | Interval between data points (e.g., `15m`, `1h`). Required |
| `timeout` | Query timeout override |

**Response:**

```json
{
  "status": "success",
  "data": {
    "resultType": "matrix",
    "result": [
      {
        "metric": {"__name__": "up", "job": "prometheus"},
        "values": [[1609459200, "1"], [1609462800, "1"]]
      }
    ]
  }
}
```

### Series Metadata

```bash
# List all label names
curl http://localhost:8428/prometheus/api/v1/labels

# List values for a specific label
curl http://localhost:8428/prometheus/api/v1/label/job/values

# Find series matching a selector
curl 'http://localhost:8428/prometheus/api/v1/series' \
  -d 'match[]=vm_http_request_errors_total'

# Get metric metadata
curl http://localhost:8428/api/v1/metadata

# TSDB status / cardinality
curl http://localhost:8428/prometheus/api/v1/status/tsdb

# Cluster equivalents (add /select/0/prometheus/ prefix)
curl http://<vmselect>:8481/select/0/prometheus/api/v1/labels
curl http://<vmselect>:8481/select/0/prometheus/api/v1/label/job/values
curl 'http://<vmselect>:8481/select/0/prometheus/api/v1/series' \
  -d 'match[]=vm_http_request_errors_total'
```

Optional parameters for label/series endpoints: `start`, `end`, `limit`, `match[]`.

### Federation

```bash
# Single-node
curl 'http://localhost:8428/federate' -d 'match[]=vm_http_request_errors_total'

# Cluster
curl 'http://<vmselect>:8481/select/0/prometheus/federate' \
  -d 'match[]=vm_http_request_errors_total'
```

### Graphite API

```bash
curl 'http://localhost:8428/graphite/metrics/find' -d 'query=vm_http_request_errors_total'
```

---

## Export APIs

### JSON Lines Export

```bash
# Single-node
curl 'http://localhost:8428/api/v1/export' \
  -d 'match[]=vm_http_request_errors_total' > data.json

# With time range
curl 'http://localhost:8428/api/v1/export' \
  -d 'match[]=up' -d 'start=-1h' -d 'end=now' > data.json

# Cluster
curl 'http://<vmselect>:8481/select/0/prometheus/api/v1/export' \
  -d 'match[]=vm_http_request_errors_total' > data.json
```

Parameters: `match[]` (required), `start`, `end`, `max_rows_per_line`. Supports `Accept-Encoding: gzip`.

### CSV Export

```bash
curl 'http://localhost:8428/api/v1/export/csv' \
  -d 'format=__name__,job,instance,__value__,__timestamp__:unix_s' \
  -d 'match[]=demo' > demo.csv

# Cluster
curl 'http://<vmselect>:8481/select/0/prometheus/api/v1/export/csv' \
  -d 'format=__name__,job,instance,__value__,__timestamp__:unix_s' \
  -d 'match[]=demo' > demo.csv
```

### Native Binary Export

Most efficient format for backups and migrations:

```bash
curl 'http://localhost:8428/api/v1/export/native' \
  -d 'match[]=vm_http_request_errors_total' > data.bin

# Cluster
curl 'http://<vmselect>:8481/select/0/prometheus/api/v1/export/native' \
  -d 'match[]=vm_http_request_errors_total' > data.bin
```

---

## Admin APIs

### Delete Series

```bash
# Single-node
curl -v 'http://localhost:8428/api/v1/admin/tsdb/delete_series' \
  -d 'match[]=vm_http_request_errors_total'

# Cluster
curl -v 'http://<vmselect>:8481/delete/0/prometheus/api/v1/admin/tsdb/delete_series' \
  -d 'match[]=vm_http_request_errors_total'
```

Returns HTTP 204 on success. Protected by `-deleteAuthKey` flag if set.

### Snapshots

```bash
# Create snapshot
curl http://localhost:8428/snapshot/create
# Response: {"status":"ok","snapshot":"<snapshot-name>"}

# List snapshots
curl http://localhost:8428/snapshot/list

# Delete specific snapshot
curl 'http://localhost:8428/snapshot/delete?snapshot=<name>'

# Delete all snapshots
curl http://localhost:8428/snapshot/delete_all

# Cluster (on vmstorage)
curl http://<vmstorage>:8482/snapshot/create
```

### Force Merge

```bash
# Merge a specific partition
curl 'http://localhost:8428/internal/force_merge?partition_prefix=2024_01'

# Cluster (on vmstorage)
curl 'http://<vmstorage>:8482/internal/force_merge'
```

### Cache Reset

```bash
curl -Is http://localhost:8428/internal/resetRollupResultCache
```

### Query Monitoring

```bash
# Currently executing queries
curl http://localhost:8428/api/v1/status/active_queries

# Top queries by frequency, duration
curl 'http://localhost:8428/api/v1/status/top_queries?topN=10&maxLifetime=30m'

# Total series count
curl http://localhost:8428/api/v1/series/count
```

### Health Check

```bash
curl http://localhost:8428/health
# vmagent
curl http://localhost:8429/ready
```

### Metrics (Prometheus format)

```bash
# Single-node
curl http://localhost:8428/metrics

# Cluster components
curl http://<vminsert>:8480/metrics
curl http://<vmselect>:8481/metrics
curl http://<vmstorage>:8482/metrics

# vmagent
curl http://localhost:8429/metrics
```

---

## MetricsQL Reference

MetricsQL is a PromQL-compatible query language with extensions. Key differences from PromQL:

- `rate()` and `increase()` consider the last sample before the lookbehind window, returning exact results for slow-changing counters.
- Scalar and instant vector types are treated identically.
- NaN values are removed from output.
- Metric names are preserved after neutral functions (`min_over_time`, `round`).
- Supports `default`, `if`, `ifnot` binary operators.
- Supports `keep_metric_names` modifier.
- Supports `limit N` suffix on aggregations.

### Filtering

```
# Simple metric selection
requests_total

# Label filtering
requests_total{code="200"}
requests_total{code=~"2.*"}
requests_total{code!="500"}

# Multi-metric regex
{__name__=~"requests_(error|success)_total"}

# OR-based label groups
{job="app1",env="prod" or job="app2",env="dev"}

# Graphite-style
{__graphite__="foo.*.bar"}
```

### Operators

**Arithmetic:** `+`, `-`, `*`, `/`, `%`, `^`

**Comparison:** `==`, `!=`, `>`, `<`, `>=`, `<=`

**Logical/Set:** `and`, `or`, `unless`

**MetricsQL-specific binary:**

- `q1 default q2` -- fill gaps in q1 with values from q2
- `q1 if q2` -- keep q1 values only where q2 exists
- `q1 ifnot q2` -- keep q1 values only where q2 is absent

**Group modifiers:** `group_left(labels)`, `group_right(labels)` with optional `prefix "..."`.

### Modifiers

```
# @ modifier (evaluate at specific time)
foo @ end()
foo @ (end() - 1h)

# offset modifier
rate(metric[5m] offset 1h)

# keep_metric_names (preserve __name__ through functions)
rate(requests_total[5m]) keep_metric_names

# limit on aggregations
sum(requests_total) by (job) limit 10
```

### Lookbehind Window and Subqueries

```
# Explicit window
rate(requests_total[5m])

# Auto window (uses step or scrape_interval)
rate(requests_total)

# Step-based window
rate(m[10i] offset 5i)

# Subquery
avg_over_time(sum(rate(metric[1i])) by (label)[5i:1i])
```

### WITH Templates

```
WITH (
  commonFilters = {job="app", env="prod"},
  errorRate = rate(errors_total{commonFilters}[5m])
)
errorRate / rate(requests_total{commonFilters}[5m])
```

### Numeric Literals

- Underscores for readability: `1_234_567`
- Metric suffixes: `8K` (8000), `1.2Mi` (1.2 * 1024^2), `1G`, `1T`
- Duration suffixes on numbers: `[300]` = 300 seconds

### Rollup Functions

Functions that aggregate raw samples within a lookbehind window `[d]`:

| Function | Description |
|----------|-------------|
| `avg_over_time(series[d])` | Average value |
| `min_over_time(series[d])` | Minimum value |
| `max_over_time(series[d])` | Maximum value |
| `sum_over_time(series[d])` | Sum of values |
| `count_over_time(series[d])` | Number of samples |
| `last_over_time(series[d])` | Last sample value |
| `first_over_time(series[d])` | First sample value |
| `median_over_time(series[d])` | Median value |
| `stddev_over_time(series[d])` | Standard deviation |
| `stdvar_over_time(series[d])` | Standard variance |
| `quantile_over_time(phi, series[d])` | phi-quantile (0 to 1) |
| `quantiles_over_time("label", phi1, ..., phiN, series[d])` | Multiple quantiles |
| `rate(series[d])` | Average per-second increase rate |
| `irate(series[d])` | Instant per-second rate from last two samples |
| `increase(series[d])` | Total increase over window |
| `delta(series[d])` | Difference between last pre-window and last in-window sample |
| `idelta(series[d])` | Difference between last two samples |
| `deriv(series[d])` | Per-second derivative via linear regression |
| `deriv_fast(series[d])` | Per-second derivative from first/last samples |
| `predict_linear(series[d], t)` | Predict value t seconds in the future |
| `holt_winters(series[d], sf, tf)` | Double exponential smoothing |
| `changes(series[d])` | Count of value changes |
| `resets(series[d])` | Count of counter resets |
| `absent_over_time(series[d])` | Returns 1 if no samples in window |
| `present_over_time(series[d])` | Returns 1 if at least one sample exists |
| `histogram_over_time(series[d])` | Build histogram for histogram_quantile |
| `scrape_interval(series[d])` | Average interval between samples |
| `timestamp(series[d])` | Unix timestamp of last sample |
| `tfirst_over_time(series[d])` | Timestamp of first sample |
| `tlast_over_time(series[d])` | Timestamp of last sample |
| `tmax_over_time(series[d])` | Timestamp of max value |
| `tmin_over_time(series[d])` | Timestamp of min value |
| `count_eq_over_time(series[d], N)` | Count samples equal to N |
| `count_gt_over_time(series[d], N)` | Count samples greater than N |
| `count_le_over_time(series[d], N)` | Count samples less than or equal to N |
| `count_ne_over_time(series[d], N)` | Count samples not equal to N |
| `share_gt_over_time(series[d], N)` | Fraction of samples greater than N |
| `share_le_over_time(series[d], N)` | Fraction of samples less than or equal to N |
| `share_eq_over_time(series[d], N)` | Fraction of samples equal to N |
| `sum_eq_over_time(series[d], N)` | Sum of samples equal to N |
| `sum_gt_over_time(series[d], N)` | Sum of samples greater than N |
| `sum_le_over_time(series[d], N)` | Sum of samples less than or equal to N |
| `range_over_time(series[d])` | max - min across samples |
| `mad_over_time(series[d])` | Median absolute deviation |
| `geomean_over_time(series[d])` | Geometric mean |
| `mode_over_time(series[d])` | Most frequent value |
| `zscore_over_time(series[d])` | Z-score for values |
| `distinct_over_time(series[d])` | Count of unique values |
| `increases_over_time(series[d])` | Count of upward transitions |
| `decreases_over_time(series[d])` | Count of downward transitions |
| `integrate(series[d])` | Integral over samples |
| `lag(series[d])` | Seconds since last sample |
| `lifetime(series[d])` | Duration between first and last samples |
| `duration_over_time(series[d], max_interval)` | Seconds series was present |
| `ascent_over_time(series[d])` | Total upward change |
| `descent_over_time(series[d])` | Total downward change |
| `rollup(series[d])` | Returns min/max/avg |
| `rollup_candlestick(series[d])` | OHLC values |
| `rollup_rate(series[d])` | Min/max/avg rates |
| `rollup_delta(series[d])` | Min/max/avg deltas |
| `rollup_increase(series[d])` | Min/max/avg increases |
| `rollup_deriv(series[d])` | Min/max/avg derivatives |
| `rollup_scrape_interval(series[d])` | Min/max/avg scrape intervals |
| `aggr_over_time(("fn1","fn2",...), series[d])` | Multiple rollup functions at once |
| `hoeffding_bound_lower(phi, series[d])` | Lower Hoeffding bound |
| `hoeffding_bound_upper(phi, series[d])` | Upper Hoeffding bound |
| `outlier_iqr_over_time(series[d])` | Returns last sample if outlier by IQR |

### Transform Functions

Functions that operate on query results:

| Function | Description |
|----------|-------------|
| `abs(q)` | Absolute value |
| `ceil(q)` | Round up |
| `floor(q)` | Round down |
| `round(q, nearest)` | Round to nearest |
| `sqrt(q)` | Square root |
| `ln(q)`, `log2(q)`, `log10(q)` | Logarithms |
| `exp(q)` | Exponential |
| `sgn(q)` | Sign (-1, 0, 1) |
| `clamp(q, min, max)` | Constrain between min and max |
| `clamp_min(q, min)` | Set minimum |
| `clamp_max(q, max)` | Set maximum |
| `absent(q)` | Returns 1 if q is empty |
| `sort(q)` | Sort ascending |
| `sort_desc(q)` | Sort descending |
| `sort_by_label(q, "label1", ...)` | Sort by label values |
| `sort_by_label_desc(q, "label1", ...)` | Sort by label descending |
| `limit_offset(limit, offset, q)` | Pagination of series |
| `drop_empty_series(q)` | Remove series with no samples |
| `interpolate(q)` | Fill gaps with linear interpolation |
| `keep_last_value(q)` | Fill gaps with last value |
| `keep_next_value(q)` | Fill gaps with next value |
| `histogram_quantile(phi, buckets)` | Quantile from histogram buckets |
| `histogram_quantiles("label", phi1,...,phiN, buckets)` | Multiple quantiles |
| `histogram_avg(buckets)` | Average from histogram |
| `histogram_stddev(buckets)` | Std dev from histogram |
| `histogram_share(le, buckets)` | Share below threshold |
| `histogram_fraction(lower, upper, buckets)` | Share between bounds |
| `prometheus_buckets(buckets)` | Convert vmrange to le buckets |
| `buckets_limit(limit, buckets)` | Limit histogram bucket count |
| `now()` | Current unix timestamp |
| `time()` | Current unix timestamp |
| `start()` | Query range start timestamp |
| `end()` | Query range end timestamp |
| `pi()` | Pi constant |
| `vector(q)` | Convert scalar to vector |
| `hour(q)`, `minute(q)`, `month(q)`, `year(q)` | Time components |
| `day_of_week(q)`, `day_of_month(q)`, `day_of_year(q)` | Date components |
| `days_in_month(q)` | Days in month |
| `timezone_offset("tz")` | Timezone offset in seconds |
| `sin(q)`, `cos(q)`, `tan(q)` | Trigonometric |
| `asin(q)`, `acos(q)`, `atan(q)` | Inverse trig |
| `sinh(q)`, `cosh(q)`, `tanh(q)` | Hyperbolic |
| `asinh(q)`, `acosh(q)`, `atanh(q)` | Inverse hyperbolic |
| `deg(q)`, `rad(q)` | Degree/radian conversion |
| `trunc(q)` | Truncate to integer |
| `bitmap_and(q, mask)` | Bitwise AND |
| `bitmap_or(q, mask)` | Bitwise OR |
| `bitmap_xor(q, mask)` | Bitwise XOR |
| `rand(seed)` | Random [0,1] uniform |
| `rand_normal(seed)` | Random normal distribution |
| `rand_exponential(seed)` | Random exponential distribution |
| `range_avg(q)` | Average across all time points |
| `range_min(q)`, `range_max(q)` | Min/max across range |
| `range_first(q)`, `range_last(q)` | First/last in range |
| `range_median(q)` | Median across range |
| `range_quantile(phi, q)` | Quantile across range |
| `range_stddev(q)`, `range_stdvar(q)` | Std dev/var across range |
| `range_mad(q)` | Median absolute deviation across range |
| `range_normalize(q1, ...)` | Normalize to [0,1] |
| `range_linear_regression(q)` | Linear regression |
| `range_trim_spiky_points(lookbehind, q)` | Remove outliers |
| `range_trim_zscore(zscore, q)` | Remove by z-score threshold |

### Aggregate Functions

Functions that combine multiple series. All support `by (labels)` or `without (labels)` grouping, and optional `limit N`.

| Function | Description |
|----------|-------------|
| `sum(q) by (labels)` | Sum across series |
| `avg(q) by (labels)` | Average |
| `min(q) by (labels)` | Minimum |
| `max(q) by (labels)` | Maximum |
| `count(q) by (labels)` | Count of series |
| `median(q) by (labels)` | Median |
| `mode(q) by (labels)` | Most frequent value |
| `stddev(q) by (labels)` | Standard deviation |
| `stdvar(q) by (labels)` | Standard variance |
| `sum2(q) by (labels)` | Sum of squares |
| `geomean(q) by (labels)` | Geometric mean |
| `group(q) by (labels)` | Group series, return 1 |
| `distinct(q) by (labels)` | Count of distinct values |
| `count_values("label", q)` | Count by value |
| `quantile(phi, q) by (labels)` | phi-quantile |
| `topk(k, q)` | Top k series by value |
| `bottomk(k, q)` | Bottom k series |
| `topk_avg(k, q)` | Top k by average |
| `topk_max(k, q)` | Top k by max |
| `topk_min(k, q)` | Top k by min |
| `topk_median(k, q)` | Top k by median |
| `topk_last(k, q)` | Top k by last value |
| `bottomk_avg(k, q)` | Bottom k by average |
| `bottomk_max(k, q)` | Bottom k by max |
| `bottomk_min(k, q)` | Bottom k by min |
| `bottomk_median(k, q)` | Bottom k by median |
| `bottomk_last(k, q)` | Bottom k by last value |
| `limitk(k, q)` | Keep k series per group |

### Label Manipulation Functions

| Function | Description |
|----------|-------------|
| `label_set(q, "k1", "v1", ...)` | Set label values |
| `label_del(q, "label1", ...)` | Delete labels |
| `label_copy(q, "src", "dst")` | Copy label |
| `label_move(q, "src", "dst")` | Rename label |
| `label_join(q, "dst", "sep", "src1", ...)` | Join labels into one |
| `label_replace(q, "dst", "replacement", "src", "regex")` | Regex-based label transformation |
| `label_transform(q, "label", "regexp", "replacement")` | Transform label values |
| `label_match(q, "label", "regex")` | Keep matching series |
| `label_mismatch(q, "label", "regex")` | Keep non-matching series |
| `label_uppercase(q, "label1", ...)` | Labels to uppercase |
| `label_lowercase(q, "label1", ...)` | Labels to lowercase |
| `label_graphite_group(q, groupNum)` | Extract Graphite group |
| `labels_equal(q1, q2)` | Keep series with identical labels |

---

## Configuration Flags

### Storage

| Flag | Description | Default |
|------|-------------|---------|
| `-storageDataPath` | Data directory | `victoria-metrics-data` |
| `-retentionPeriod` | Data retention duration | `31d` (minimum 24h) |
| `-dedup.minScrapeInterval` | Deduplication interval for identical samples | disabled |
| `-storage.minFreeDiskSpaceBytes` | Minimum free disk space (auto read-only below this) | `10MB` |

### Resource Limits

| Flag | Description |
|------|-------------|
| `-maxIngestionRate` | Max samples/second ingestion rate |
| `-memory.allowedPercent` | Max % of system RAM for caches |
| `-memory.allowedBytes` | Max bytes for caches |
| `-search.maxMemoryPerQuery` | Max memory per query |
| `-search.maxConcurrentRequests` | Concurrent query limit |
| `-search.maxQueryDuration` | Query timeout |
| `-search.maxUniqueTimeseries` | Max series per query |
| `-search.maxSamplesPerQuery` | Max samples per query |
| `-search.maxSamplesPerSeries` | Max samples per series |
| `-search.maxSeries` | Max series for `/api/v1/series` |
| `-search.maxTagKeys` | Max results for `/api/v1/labels` |
| `-search.maxTagValues` | Max results for `/api/v1/label/.../values` |
| `-search.maxExportSeries` | Max series for export endpoints |
| `-search.maxFederateSeries` | Max series for `/federate` |
| `-search.maxLabelsAPISeries` | Max series scanned for label endpoints |
| `-search.maxLabelsAPIDuration` | Timeout for label queries |
| `-search.maxExportDuration` | Export API timeout |
| `-search.maxQueueDuration` | Wait time when concurrency limit reached |
| `-search.maxDeleteSeries` | Max series for delete operations |
| `-search.latencyOffset` | Latency offset to avoid incomplete data (default 30s) |

### Security

| Flag | Description |
|------|-------------|
| `-metricsAuthKey` | Auth key to protect `/metrics` endpoint |
| `-deleteAuthKey` | Auth key to protect delete_series API |

Use `vmauth` (auth proxy and load balancer) or `vmgateway` (per-tenant rate limiting) for full authentication and authorization.

### Scraping

| Flag | Description |
|------|-------------|
| `-promscrape.config` | Path to Prometheus-compatible scrape config YAML |
| `-relabelConfig` | Path to relabel config file (supports HTTP URLs) |

### Protocol Listeners

| Flag | Description |
|------|-------------|
| `-graphiteListenAddr` | Enable Graphite plaintext (default port 2003) |
| `-opentsdbListenAddr` | Enable OpenTSDB telnet (default port 4242) |
| `-opentsdbHTTPListenAddr` | Enable OpenTSDB HTTP API |

### Environment Variables

Enable with `-envflag.enable`. Set prefix with `-envflag.prefix=VM_`. Flag names map by replacing `.` with `_`:

```bash
export VM_retentionPeriod=90d
export VM_storageDataPath=/data/vm
```

---

## Cluster API URL Reference

### Ingestion (vminsert)

All paths: `http://<vminsert>:8480/insert/<accountID>/<suffix>`

| Suffix | Protocol |
|--------|----------|
| `prometheus/api/v1/write` | Prometheus remote write |
| `prometheus/api/v1/import` | JSON lines |
| `prometheus/api/v1/import/native` | Native binary |
| `prometheus/api/v1/import/csv` | CSV |
| `prometheus/api/v1/import/prometheus` | Prometheus text |
| `opentelemetry/v1/metrics` | OpenTelemetry |
| `datadog/api/v1/series` | DataDog v1 |
| `datadog/api/v2/series` | DataDog v2 |
| `influx/write` | InfluxDB line protocol |
| `influx/api/v2/write` | InfluxDB v2 |
| `opentsdb/api/put` | OpenTSDB HTTP |

### Querying (vmselect)

All paths: `http://<vmselect>:8481/select/<accountID>/prometheus/<suffix>`

| Suffix | Purpose |
|--------|---------|
| `api/v1/query` | Instant query |
| `api/v1/query_range` | Range query |
| `api/v1/series` | Find series |
| `api/v1/labels` | List label names |
| `api/v1/label/<name>/values` | Label values |
| `api/v1/export` | JSON export |
| `api/v1/export/native` | Native export |
| `api/v1/export/csv` | CSV export |
| `api/v1/status/tsdb` | TSDB cardinality |
| `api/v1/metadata` | Metric metadata |
| `federate` | Prometheus federation |

### Multi-Tenant Endpoints

Use `multitenant` instead of `<accountID>`:

```
http://<vminsert>:8480/insert/multitenant/<suffix>
http://<vmselect>:8481/select/multitenant/<suffix>
```

These take the tenant from `vm_account_id` and `vm_project_id` labels in the data.

### Tenant Discovery

```bash
curl 'http://<vmselect>:8481/admin/tenants?start=...&end=...'
```

### Cluster Administration

```bash
# Snapshots (on vmstorage)
curl http://<vmstorage>:8482/snapshot/create
curl http://<vmstorage>:8482/snapshot/list
curl 'http://<vmstorage>:8482/snapshot/delete?snapshot=<name>'

# Force merge (on vmstorage)
curl http://<vmstorage>:8482/internal/force_merge

# Delete series (on vmselect)
curl 'http://<vmselect>:8481/delete/<accountID>/prometheus/api/v1/admin/tsdb/delete_series' \
  -d 'match[]=metric_name'
```

---

## Cluster Configuration

### Replication

Set `-replicationFactor=N` on vminsert to store N copies on distinct vmstorage nodes. Set `-dedup.minScrapeInterval=1ms` on vmselect for deduplication. The cluster needs at least `2*N-1` vmstorage nodes.

### vmstorage Groups

```bash
vmselect \
  -storageNode=g1/host1,g1/host2,g1/host3 \
  -storageNode=g2/host4,g2/host5,g2/host6 \
  -replicationFactor=g1:3 -replicationFactor=g2:2
```

### Key Cluster Flags

| Component | Flag | Description |
|-----------|------|-------------|
| vminsert | `-replicationFactor=N` | Number of vmstorage copies |
| vminsert | `-disableReroutingOnUnavailable` | Pause ingestion instead of re-routing |
| vmselect | `-replicationFactor=N` | Tolerate N-1 node failures |
| vmselect | `-dedup.minScrapeInterval` | Deduplication interval |
| vmselect | `-search.denyPartialResponse` | Reject partial responses |
| vmstorage | `-storage.minFreeDiskSpaceBytes` | Auto read-only threshold |
| vmstorage | `-storage.vminsertConnsShutdownDuration` | Graceful connection close interval |

---

## vmagent Configuration

### Scraping

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'my-app'
    scrape_interval: 15s
    static_configs:
      - targets: ['localhost:9090']
```

```bash
vmagent -promscrape.config=prometheus.yml \
  -remoteWrite.url=http://victoriametrics:8428/api/v1/write
```

### Key vmagent Flags

| Flag | Description |
|------|-------------|
| `-remoteWrite.url` | Target endpoint(s) for metrics |
| `-remoteWrite.tmpDataPath` | Buffer directory when remote unavailable |
| `-remoteWrite.maxDiskUsagePerURL` | Max disk space for buffer per URL |
| `-remoteWrite.forceVMProto` | Force VictoriaMetrics protocol (2-5x bandwidth reduction) |
| `-remoteWrite.forcePromProto` | Force Prometheus protocol |
| `-remoteWrite.label=key=value` | Add labels to all metrics |
| `-remoteWrite.relabelConfig` | Global relabeling rules |
| `-remoteWrite.urlRelabelConfig` | Per-URL relabeling rules |
| `-remoteWrite.shardByURL` | Distribute series across URLs |
| `-remoteWrite.maxHourlySeries` | Max unique series per hour |
| `-remoteWrite.maxDailySeries` | Max unique series per day |
| `-promscrape.config` | Prometheus scrape config path |
| `-promscrape.cluster.membersCount` | Number of vmagent instances for sharding |
| `-promscrape.cluster.memberNum` | This instance's ID (0 to N-1) |
| `-promscrape.cluster.replicationFactor` | Replication across cluster members |
| `-promscrape.seriesLimitPerTarget` | Series limit per scrape target |
| `-streamAggr.config` | Stream aggregation config file |
| `-streamAggr.dedupInterval` | Deduplication interval |
| `-enableMultitenantHandlers` | Accept `/insert/<accountID>/...` endpoints |

### vmagent Ingestion Endpoints (port 8429)

| Protocol | Endpoint |
|----------|----------|
| Prometheus remote write | `/api/v1/write` |
| Prometheus text | `/api/v1/import/prometheus` |
| JSON lines | `/api/v1/import` |
| CSV | `/api/v1/import/csv` |
| Native | `/api/v1/import/native` |
| InfluxDB | `/write` |
| DataDog | `/datadog/api/v1/series`, `/datadog/api/v2/series` |
| OpenTelemetry | (OTLP HTTP) |
| Graphite | via `-graphiteListenAddr` |
| OpenTSDB | via `-opentsdbListenAddr` |

### vmagent Status Endpoints

| Endpoint | Purpose |
|----------|---------|
| `/targets` | Current scrape target status |
| `/service-discovery` | Discovered targets with labels |
| `/api/v1/targets` | Prometheus-compatible JSON targets API |
| `/ready` | Health check (200 when initialized) |
| `/config` | Current active configuration |
| `/-/reload` | Reload configuration (POST) |
| `/metrics` | Prometheus metrics for monitoring vmagent |

### Auto-Generated Scrape Metrics

When vmagent scrapes a target, it generates these metrics:

- `up`: 1 for success, 0 for failure
- `scrape_duration_seconds`: Scrape duration
- `scrape_response_size_bytes`: Response size
- `scrape_samples_scraped`: Samples parsed
- `scrape_samples_post_metric_relabeling`: Samples after relabeling
- `scrape_series_added`: New series count
- `scrape_series_current`: Current series count

---

## Common Patterns

### Push metrics via Prometheus text format

```bash
curl -d 'http_requests_total{method="GET",path="/"} 1027' \
  http://localhost:8428/api/v1/import/prometheus
```

### Query and pipe to jq

```bash
curl -s 'http://localhost:8428/prometheus/api/v1/query' \
  -d 'query=up' | jq '.data.result'
```

### Backup and restore via native format

```bash
# Export
curl 'http://localhost:8428/api/v1/export/native' \
  -d 'match[]={__name__!=""}' > backup.bin

# Import to another instance
curl -X POST http://new-instance:8428/api/v1/import/native -T backup.bin
```

### Migrate from InfluxDB

```bash
curl -d 'cpu_usage,host=server1 value=0.64' \
  http://localhost:8428/write
```

### Stream aggregation config example

```yaml
# stream-aggr.yaml
- match: 'http_requests_total'
  interval: 1m
  outputs: [total, increase]
  by: [job, instance]
```
