---
name: pxc-cluster
description: "Percona XtraDB Cluster (PXC) - Multi-master MySQL cluster based on Galera with synchronous replication, certification-based conflict resolution, and automatic node provisioning."
metadata:
  languages: "sql,bash,ini"
  versions: "8.0.45-36"
  revision: 1
  updated-on: "2026-03-09"
  source: community
  tags: "percona,pxc,mysql,galera,cluster,replication,high-availability,wsrep"
---

# Percona XtraDB Cluster (PXC) - Configuration and Operations Guide

You are a Percona XtraDB Cluster expert. Help me configure, manage, and troubleshoot PXC clusters with Galera synchronous replication.

## Golden Rule: Understand the Galera Replication Model

Percona XtraDB Cluster is a multi-master MySQL clustering solution based on the Galera library. Every node is both a reader and a writer. Replication is synchronous and certification-based -- not the traditional MySQL async/semi-sync replication.

- **Database Engine:** Percona Server for MySQL 8.0 (MySQL 8.0 compatible)
- **Replication Library:** Galera 4 (wsrep API)
- **Current Version:** PXC 8.0.45-36
- **Documentation:** https://docs.percona.com/percona-xtradb-cluster/8.0/

**Key differentiators from standard MySQL replication:**

| Feature | Standard MySQL | Percona XtraDB Cluster |
|---------|---------------|----------------------|
| Replication type | Asynchronous / Semi-synchronous | Synchronous |
| Topology | Master-slave | Multi-master (all nodes writable) |
| Conflict resolution | Last-write-wins / manual | Certification-based (automatic) |
| Data consistency | Eventual (lag possible) | Strong (no lag between nodes) |
| Node provisioning | Manual setup | Automatic (SST/IST) |
| Parallel replication | Logical clock based | Row-level write-set based |

---

## Architecture

### How Galera Replication Works

1. **Transaction Execution**: Client sends a transaction to any node. The transaction executes locally using InnoDB.
2. **Write-Set Creation**: At COMMIT time, Galera captures the row changes into a "write-set" containing the changed rows and primary keys.
3. **Certification**: The write-set is broadcast to all nodes via group communication (GComm). Each node independently runs certification -- checking whether the write-set conflicts with any locally pending transactions.
4. **Apply or Abort**: If certification passes on all nodes, the transaction commits everywhere. If it fails (conflict detected), the originating transaction is rolled back. Remote nodes apply the write-set through applier threads.

### Components

- **Percona Server for MySQL**: The base MySQL 8.0 database engine with XtraDB storage engine
- **Galera Library** (`libgalera_smm.so`): Provides the wsrep replication plugin
  - CentOS/RHEL path: `/usr/lib64/libgalera_smm.so`
  - Debian/Ubuntu path: `/usr/lib/libgalera_smm.so`
- **wsrep API**: Standardized interface between the database and the replication library
- **GComm**: Group communication transport layer handling node membership and message ordering

### Cluster States

| State | Description |
|-------|-------------|
| `Primary` | Normal operating state; cluster has quorum |
| `Non-Primary` | Node lost quorum; read-only if `wsrep_dirty_reads=ON`, otherwise unavailable |
| `Disconnected` | Node is not part of any cluster |

### Node States

| State | wsrep_local_state | Description |
|-------|-------------------|-------------|
| Joining | 1 | Node is joining the cluster, requesting SST or IST |
| Donor/Desynced | 2 | Node is sending state to a joiner; temporarily desynced |
| Joined | 3 | Node has received state but not yet synced with cluster |
| Synced | 4 | Normal operating state; fully synchronized |

---

## Core Configuration

### Minimal my.cnf for a 3-Node Cluster

**Node 1 (Bootstrap node):**

```ini
[mysqld]
# PXC/Galera settings
wsrep_provider=/usr/lib64/libgalera_smm.so
wsrep_cluster_name=my_pxc_cluster
wsrep_cluster_address=gcomm://192.168.0.1,192.168.0.2,192.168.0.3
wsrep_node_name=node1
wsrep_node_address=192.168.0.1

# SST method
wsrep_sst_method=xtrabackup-v2

# InnoDB settings (required for Galera)
binlog_format=ROW
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2

# Encryption
pxc_encrypt_cluster_traffic=ON
```

**Node 2:**

```ini
[mysqld]
wsrep_provider=/usr/lib64/libgalera_smm.so
wsrep_cluster_name=my_pxc_cluster
wsrep_cluster_address=gcomm://192.168.0.1,192.168.0.2,192.168.0.3
wsrep_node_name=node2
wsrep_node_address=192.168.0.2
wsrep_sst_method=xtrabackup-v2
binlog_format=ROW
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2
pxc_encrypt_cluster_traffic=ON
```

**Node 3:**

```ini
[mysqld]
wsrep_provider=/usr/lib64/libgalera_smm.so
wsrep_cluster_name=my_pxc_cluster
wsrep_cluster_address=gcomm://192.168.0.1,192.168.0.2,192.168.0.3
wsrep_node_name=node3
wsrep_node_address=192.168.0.3
wsrep_sst_method=xtrabackup-v2
binlog_format=ROW
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2
pxc_encrypt_cluster_traffic=ON
```

### Required InnoDB Settings for Galera

| Setting | Required Value | Reason |
|---------|---------------|--------|
| `binlog_format` | `ROW` | Galera requires row-based replication |
| `default_storage_engine` | `InnoDB` | Only InnoDB supports Galera replication |
| `innodb_autoinc_lock_mode` | `2` (interleaved) | Required for multi-master auto-increment safety |

---

## wsrep System Variables Reference

### Cluster Identity and Membership

| Variable | Scope | Dynamic | Default | Description |
|----------|-------|---------|---------|-------------|
| `wsrep_cluster_name` | Global | No | `my_wsrep_cluster` | Cluster identifier; must match on all nodes (max 32 chars) |
| `wsrep_cluster_address` | Global | No | - | `gcomm://ip1,ip2,ip3` format; empty for bootstrap |
| `wsrep_node_name` | Global | Yes | hostname | Human-readable node identifier |
| `wsrep_node_address` | Global | No | First NIC IP:4567 | Node's network address for cluster communication |
| `wsrep_node_incoming_address` | Global | No | `AUTO` | Expected client connection address |

### State Transfer

| Variable | Scope | Dynamic | Default | Description |
|----------|-------|---------|---------|-------------|
| `wsrep_sst_method` | Global | Yes | `xtrabackup-v2` | SST method: `xtrabackup-v2`, `clone`, `ist_only` |
| `wsrep_sst_donor` | Global | Yes | - | Preferred donor nodes (comma-separated names; trailing comma = allow fallback) |
| `wsrep_sst_receive_address` | Global | Yes | `AUTO` | Address where joiner receives SST |
| `wsrep_sst_allowed_methods` | Global | No | `xtrabackup-v2, clone` | Accepted SST methods (PXC 8.0.41+) |
| `sst_idle_timeout` | Global | No | `120` | Max idle seconds during SST (-1 = no timeout) |

### Applier / Parallel Replication

| Variable | Scope | Dynamic | Default | Description |
|----------|-------|---------|---------|-------------|
| `wsrep_applier_threads` | Global | Yes | `1` | Number of parallel applier threads |
| `wsrep_applier_FK_checks` | Global | Yes | `ON` | Foreign key checking for applier |
| `wsrep_applier_UK_checks` | Global | Yes | `OFF` | Unique key checking for applier |
| `wsrep_certify_nonPK` | Global | No | `ON` | Auto-generate PKs for tables without them |

### Transaction and Write-Set Limits

| Variable | Scope | Dynamic | Default | Description |
|----------|-------|---------|---------|-------------|
| `wsrep_max_ws_size` | Global | Yes | `2147483647` (2 GB) | Max write-set size in bytes |
| `wsrep_max_ws_rows` | Global | Yes | `0` (unlimited) | Max rows per write-set |
| `wsrep_certification_rules` | Global | Yes | `STRICT` | `STRICT` or `OPTIMIZED` (relaxed FK certification) |

### Synchronization and Causality

| Variable | Scope | Dynamic | Default | Description |
|----------|-------|---------|---------|-------------|
| `wsrep_sync_wait` | Session/Global | Yes | `0` | Bitmask for causality checks: 0=none, 1=READ, 2=UPDATE/DELETE, 4=INSERT, 7=all |
| `wsrep_causal_reads` | Session/Global | Yes | `OFF` | Deprecated; equivalent to `wsrep_sync_wait=1` |

### Replication Control

| Variable | Scope | Dynamic | Default | Description |
|----------|-------|---------|---------|-------------|
| `wsrep_on` | Session | Yes | `ON` | Enable/disable replication for current session |
| `wsrep_desync` | Global | Yes | `OFF` | Disable flow control; node falls behind indefinitely |
| `wsrep_dirty_reads` | Session/Global | Yes | `OFF` | Allow reads when cluster connectivity is lost |
| `wsrep_reject_queries` | Global | Yes | `NONE` | Reject client queries: `NONE`, `ALL`, `ALL_KILL` |
| `wsrep_replicate_myisam` | Session/Global | No | `OFF` | Replicate MyISAM DML (experimental) |

### Auto-Increment

| Variable | Scope | Dynamic | Default | Description |
|----------|-------|---------|---------|-------------|
| `wsrep_auto_increment_control` | Global | Yes | `ON` | Auto-adjust auto_increment_increment/offset based on cluster size |
| `wsrep_retry_autocommit` | Global | No | `1` | Retry count for autocommit transactions failing certification |

### Online Schema Upgrade (OSU)

| Variable | Scope | Dynamic | Default | Description |
|----------|-------|---------|---------|-------------|
| `wsrep_OSU_method` | Session/Global | Yes | `TOI` | DDL method: `TOI` (Total Order Isolation), `RSU` (Rolling Schema Upgrade), `NBO` (Non-Blocking Operations) |
| `wsrep_RSU_commit_timeout` | Global | Yes | `5000` us | Timeout for active connections before RSU starts |

### Streaming Replication

| Variable | Scope | Dynamic | Default | Description |
|----------|-------|---------|---------|-------------|
| `wsrep_trx_fragment_size` | Session/Global | Yes | `0` | Fragment size for streaming replication (0 = disabled) |
| `wsrep_trx_fragment_unit` | Session/Global | Yes | `bytes` | Unit: `bytes`, `rows`, `statements` |
| `wsrep_SR_store` | Global | No | `table` | Storage for SR fragments: `table` or `none` |

### Strict Mode

| Variable | Scope | Dynamic | Default | Description |
|----------|-------|---------|---------|-------------|
| `pxc_strict_mode` | Global | Yes | `ENFORCING` | Validation level: `DISABLED`, `PERMISSIVE`, `ENFORCING`, `MASTER` |

### Maintenance

| Variable | Scope | Dynamic | Default | Description |
|----------|-------|---------|---------|-------------|
| `pxc_maint_mode` | Global | Yes | `DISABLED` | Node state: `DISABLED` (normal), `MAINTENANCE`, `SHUTDOWN` |
| `pxc_maint_transition_period` | Global | Yes | `10` seconds | Grace period for active transactions during maintenance transition |

### Encryption

| Variable | Scope | Dynamic | Default | Description |
|----------|-------|---------|---------|-------------|
| `pxc_encrypt_cluster_traffic` | Global | No | `ON` | Auto-configure SSL for cluster traffic |

### Debugging and Logging

| Variable | Scope | Dynamic | Default | Description |
|----------|-------|---------|---------|-------------|
| `wsrep_debug` | Global | Yes | `NONE` | Debug level: `NONE`, `SERVER`, `TRANSACTION`, `STREAMING`, `CLIENT` |
| `wsrep_min_log_verbosity` | Global | Yes | `3` | Min wsrep/Galera log verbosity (1-3) |
| `wsrep_log_conflicts` | Global | No | `OFF` | Log extended conflict info (tables, schemas, keys) |

### Recovery

| Variable | Scope | Dynamic | Default | Description |
|----------|-------|---------|---------|-------------|
| `wsrep_recover` | Global | No | `OFF` | Recover GTID from logs after crash |
| `wsrep_start_position` | Global | Yes | `00000000-...-000000:-1` | UUID:seqno initialization position |
| `wsrep_ignore_apply_errors` | Global | Yes | `0` | Error handling bitmask: 0=none, 1=DDL, 2=DML, 4=all DDL as warnings |

### Binary Log

| Variable | Scope | Dynamic | Default | Description |
|----------|-------|---------|---------|-------------|
| `wsrep_forced_binlog_format` | Global | Yes | `NONE` | Force binlog format: `ROW`, `STATEMENT`, `MIXED`, `NONE` |

---

## wsrep Provider Options (Galera Parameters)

Set via `wsrep_provider_options` in my.cnf as semicolon-separated key=value pairs:

```ini
wsrep_provider_options="gcache.size=1G;gcs.fc_limit=150;evs.send_window=256"
```

### GCache (Galera Cache) -- Critical for IST

| Option | Default | Dynamic | Description |
|--------|---------|---------|-------------|
| `gcache.size` | `128M` | No | Size of the Galera write-set cache (`galera.cache`). Larger values retain more history, improving IST chances for rejoining nodes. |
| `gcache.dir` | datadir | No | Directory for `galera.cache` file |
| `gcache.name` | `/var/lib/mysql/galera.cache` | No | Exact filename for Galera cache |
| `gcache.page_size` | `128M` | No | Individual page file size in page storage |
| `gcache.recover` | `Yes` | No | Attempt gcache recovery on startup for IST capability |
| `gcache.freeze_purge_at_seqno` | `-1` | Yes | Freeze gcache purging to retain write-sets; use `now` for immediate freezing |
| `gcache.keep_pages_count` | `0` | Yes | Limit overflow page count |
| `gcache.keep_pages_size` | `0` | No | Limit total overflow page size |

### GCache Encryption

| Option | Default | Description |
|--------|---------|-------------|
| `gcache.encryption` | `off` | Enable GCache encryption |
| `gcache.encryption_cache_page_size` | `32KB` | Page size for encrypted cache (2-512 pages) |
| `gcache.encryption_cache_size` | `16MB` | Total encryption cache capacity (2-512 pages) |
| `allocator.disk_pages_encryption` | `off` | Enable write-set cache encryption |

**Master key rotation:**

```sql
ALTER INSTANCE ROTATE GCACHE MASTER KEY;
```

### Flow Control (gcs.fc_*)

Flow control prevents slow nodes from falling too far behind by pausing replication cluster-wide.

| Option | Default | Dynamic | Description |
|--------|---------|---------|-------------|
| `gcs.fc_limit` | `100` | Yes | Pause replication when applier queue exceeds this threshold. Recalculated dynamically based on node count unless overridden. |
| `gcs.fc_factor` | `1` | Yes | Resume replication when queue drops below `fc_factor * fc_limit` |
| `gcs.fc_master_slave` | `NO` | No | When `YES`, disables dynamic fc_limit recalculation (use for single-writer topologies) |
| `gcs.fc_auto_evict_threshold` | `0.75` | No | Ratio for auto-eviction relative to `gcs.fc_auto_evict_window` (PXC 8.0.33-25+) |
| `gcs.fc_auto_evict_window` | `0` (disabled) | No | Time window for observing flow control events; node self-leaves when threshold exceeded (PXC 8.0.33-25+) |

**Monitoring flow control:**

```sql
SHOW STATUS LIKE 'wsrep_flow_control_paused';      -- Fraction of time paused (0.0-1.0)
SHOW STATUS LIKE 'wsrep_flow_control_sent';         -- Number of FC_PAUSE events sent
SHOW STATUS LIKE 'wsrep_local_recv_queue_avg';      -- Average receive queue length
```

**Tuning guidelines:**
- If `wsrep_flow_control_paused > 0.1`, a node is falling behind
- Increase `gcache.size` and `wsrep_applier_threads` on slow nodes
- Increase `gcs.fc_limit` cautiously (higher values allow more lag before pausing)
- For single-writer setups, set `gcs.fc_master_slave=YES`

### EVS (Extended Virtual Synchrony) Timing

Controls node failure detection and cluster membership.

| Option | Default | Dynamic | Description |
|--------|---------|---------|-------------|
| `evs.keepalive_period` | `PT1S` | No | Keepalive beacon frequency when no traffic |
| `evs.inactive_check_period` | `PT0.5S` | No | Peer inactivity check frequency |
| `evs.suspect_timeout` | `PT5S` | Yes | Time before inactive node is suspected |
| `evs.inactive_timeout` | `PT15S` | No | Time before node is declared dead |
| `evs.delay_margin` | `PT1S` | Yes | Permitted response delay before delayed-list entry (must exceed max RTT) |
| `evs.delayed_keep_period` | `PT30S` | Yes | Time node must be responsive to clear delayed-list entry |
| `evs.auto_evict` | `0` | Yes | Delayed-list threshold for auto-eviction (0 = disabled; requires `evs.version=1`) |
| `evs.version` | `0` | No | EVS protocol version (1 enables auto-eviction) |
| `evs.send_window` | `10` | No | Max concurrent replication packets (increase for WAN: 256-512) |
| `evs.user_send_window` | `4` | Yes | User-configurable concurrent packet limit |

**WAN optimization example:**

```ini
wsrep_provider_options="evs.send_window=256;evs.user_send_window=128;evs.inactive_timeout=PT30S;evs.suspect_timeout=PT10S;evs.keepalive_period=PT3S"
```

### Network and Quorum

| Option | Default | Description |
|--------|---------|-------------|
| `gmcast.listen_addr` | `tcp://0.0.0.0:4567` | Address for inter-node cluster connections |
| `base_port` | `4567` | Port for Galera cluster communication |
| `pc.weight` | `1` | Node weight for Weighted Quorum calculations |
| `pc.wait_prim_timeout` | `PT30S` | Wait duration for primary component before timeout |
| `pc.wait_restored_prim_timeout` | `PT0S` (infinite) | Wait for primary restoration from `gvwstate.dat` (PXC 8.0.33-25+) |
| `socket.checksum` | `2` | Checksum: 0=disabled, 1=CRC32, 2=hardware CRC32-C |
| `ist.recv_addr` | wsrep_node_address | Address for receiving IST |
| `gcs.sync_donor` | `No` | Block entire cluster if donor is blocked during SST |

---

## Node Management

### Bootstrapping a New Cluster

The first node must be started in bootstrap mode, which initializes the cluster with `wsrep_cluster_address=gcomm://` and sets `wsrep_cluster_conf_id=1`.

```bash
# Start the first node in bootstrap mode
systemctl start mysql@bootstrap
```

**Critical**: A service started with `mysql@bootstrap` must be stopped with the same command:

```bash
# CORRECT: stop bootstrapped node
systemctl stop mysql@bootstrap

# WRONG: this will NOT stop a bootstrapped instance
# systemctl stop mysql
```

**Verify bootstrap success:**

```sql
SHOW STATUS LIKE 'wsrep_cluster_size';       -- Should be 1
SHOW STATUS LIKE 'wsrep_cluster_status';      -- Should be "Primary"
SHOW STATUS LIKE 'wsrep_connected';           -- Should be "ON"
SHOW STATUS LIKE 'wsrep_ready';               -- Should be "ON"
SHOW STATUS LIKE 'wsrep_local_state_comment'; -- Should be "Synced"
```

### Adding Nodes to the Cluster

After the bootstrap node is running, start additional nodes normally:

```bash
# On node 2 and node 3
systemctl start mysql
```

Each joining node will:
1. Connect to `wsrep_cluster_address` nodes
2. Request state transfer (SST or IST depending on gcache availability)
3. Apply the received state
4. Transition through states: Joining -> Joined -> Synced

### State Snapshot Transfer (SST)

SST is a full data copy from a donor node to a joiner. It occurs when:
- A node joins for the first time
- The gcache does not contain the write-sets needed for IST
- The node's state is too far behind

**SST Methods:**

| Method | Description | Donor Impact |
|--------|-------------|--------------|
| `xtrabackup-v2` (default) | Percona XtraBackup with backup locks; donor stays operational | Minimal -- donor is not paused |
| `clone` | MySQL native clone plugin; file-level transfer | Fast, but overwrites joiner's data directory |
| `ist_only` | Refuse SST, only accept IST (PXC 8.0.33-25+) | None -- rejects nodes needing full SST |

**Important SST requirements:**
- `datadir` must be specified in my.cnf
- Local socket must be configured (cannot be empty)

**Configuring preferred SST donor:**

```ini
wsrep_sst_donor="node2,node3,"
```

The trailing comma means "allow fallback to other nodes if named donors are unavailable."

### Incremental State Transfer (IST)

IST transfers only the missing write-sets from the gcache. It is much faster than SST.

**IST occurs when:**
- The joiner's last GTID is found in a donor's gcache
- The gap between joiner and cluster can be bridged by cached write-sets

**Donor selection priority for IST:**
1. Local IST-capable nodes preferred over remote ones
2. Among multiple candidates, the node with the highest `seqno` is chosen
3. If no IST-capable donor exists, SST is triggered

**Maximize IST availability:**

```ini
# Size gcache to hold enough write-sets to cover expected downtime
wsrep_provider_options="gcache.size=2G;gcache.recover=yes"
```

**Rule of thumb for gcache sizing**: Size gcache to hold all write-sets generated during the longest expected node downtime (maintenance window, rolling upgrades, etc.).

### Graceful Node Shutdown

```bash
# Normal shutdown
systemctl stop mysql

# Or from MySQL
mysql> SET GLOBAL wsrep_reject_queries=ALL;  -- Stop accepting new queries
mysql> SHUTDOWN;
```

### Node Maintenance Mode

```sql
-- Put node in maintenance (ProxySQL-aware)
SET GLOBAL pxc_maint_mode='MAINTENANCE';

-- Perform maintenance tasks...

-- Return to normal
SET GLOBAL pxc_maint_mode='DISABLED';
```

The `pxc_maint_transition_period` (default 10 seconds) allows active transactions to complete before full maintenance mode.

### The grastate.dat File

Located in the data directory, this file records the node's last known cluster state:

```
# GALERA saved state
version: 2.1
uuid:    <cluster-UUID>
seqno:   <sequence-number>
safe_to_bootstrap: 0
```

- `safe_to_bootstrap: 1` means this node was the last to shut down and is safe to bootstrap from
- `seqno: -1` means the node crashed; run `wsrep_recover` to find the actual position

### Recovering After a Full Cluster Crash

```bash
# 1. Find the most advanced node (highest seqno)
# On each node:
mysqld --wsrep-recover
# Look for: "Recovered position: <UUID>:<seqno>"

# 2. On the node with the highest seqno, edit grastate.dat:
# Set: safe_to_bootstrap: 1

# 3. Bootstrap that node
systemctl start mysql@bootstrap

# 4. Start remaining nodes normally
# (on other nodes)
systemctl start mysql
```

---

## Performance Tuning

### Parallel Replication (Applier Threads)

Increase applier threads to improve apply throughput on replica/secondary nodes:

```ini
[mysqld]
wsrep_applier_threads=4
```

```sql
-- Change dynamically
SET GLOBAL wsrep_applier_threads=4;

-- Monitor applier performance
SHOW STATUS LIKE 'wsrep_local_recv_queue_avg';  -- Should stay close to 0
SHOW STATUS LIKE 'wsrep_cert_deps_distance';    -- Max theoretical parallelism
```

**Guidelines:**
- Set `wsrep_applier_threads` to roughly match `wsrep_cert_deps_distance`
- Start with 2-4 threads and increase while monitoring
- More threads require monitoring for consistency issues
- Diminishing returns beyond 16 threads for most workloads

### GCache Sizing

```ini
# Production recommendation: size for expected downtime
wsrep_provider_options="gcache.size=2G;gcache.recover=yes"
```

**Sizing formula**: Monitor `wsrep_local_recv_queue_avg` and write throughput. If your cluster writes ~100 MB/hour of write-sets, and you want IST coverage for 12-hour maintenance windows, set `gcache.size=1200M` minimum.

### Flow Control Tuning

```ini
# Default flow control settings
wsrep_provider_options="gcs.fc_limit=100;gcs.fc_factor=1.0"

# More lenient (allows larger queue before pausing)
wsrep_provider_options="gcs.fc_limit=200;gcs.fc_factor=0.8"

# Single-writer topology
wsrep_provider_options="gcs.fc_master_slave=YES"
```

**Monitor flow control impact:**

```sql
SHOW STATUS LIKE 'wsrep_flow_control_paused';       -- 0.0 = no pausing; > 0.1 = investigate
SHOW STATUS LIKE 'wsrep_flow_control_paused_ns';     -- Nanoseconds paused
SHOW STATUS LIKE 'wsrep_flow_control_sent';           -- FC_PAUSE messages sent by this node
SHOW STATUS LIKE 'wsrep_local_recv_queue_avg';        -- Average receive queue size
SHOW STATUS LIKE 'wsrep_local_send_queue_avg';        -- Average send queue size
```

### Network Optimization for WAN

```ini
wsrep_provider_options="evs.send_window=256;evs.user_send_window=128;evs.suspect_timeout=PT10S;evs.inactive_timeout=PT30S;evs.keepalive_period=PT3S;socket.checksum=2"
```

### Write-Set Size Management

```sql
-- Check current limits
SHOW VARIABLES LIKE 'wsrep_max_ws_size';
SHOW VARIABLES LIKE 'wsrep_max_ws_rows';

-- Large transactions can be split using streaming replication
SET SESSION wsrep_trx_fragment_size=10000;
SET SESSION wsrep_trx_fragment_unit='rows';
```

### Streaming Replication for Large Transactions

For transactions exceeding `wsrep_max_ws_size` or long-running transactions that risk certification conflicts:

```sql
-- Enable streaming replication for current session
SET SESSION wsrep_trx_fragment_size=1048576;   -- 1 MB fragments
SET SESSION wsrep_trx_fragment_unit='bytes';

-- Run your large transaction
START TRANSACTION;
-- ... large batch operations ...
COMMIT;

-- Disable streaming replication
SET SESSION wsrep_trx_fragment_size=0;
```

### InnoDB Tuning for PXC

```ini
[mysqld]
# Required
innodb_autoinc_lock_mode=2
binlog_format=ROW

# Recommended
innodb_buffer_pool_size=70%_of_RAM
innodb_log_file_size=1G
innodb_flush_log_at_trx_commit=2    # Trade durability for performance (Galera provides redundancy)
innodb_flush_method=O_DIRECT
innodb_file_per_table=1
```

---

## Online Schema Changes (DDL)

### Total Order Isolation (TOI) -- Default

DDL statements are replicated and executed simultaneously on all nodes. The entire cluster is locked for the DDL duration.

```sql
SET SESSION wsrep_OSU_method=TOI;
ALTER TABLE my_table ADD COLUMN new_col INT;
```

### Rolling Schema Upgrade (RSU)

DDL executes only on the local node. Apply to each node manually.

```sql
SET SESSION wsrep_OSU_method=RSU;
ALTER TABLE my_table ADD COLUMN new_col INT;
SET SESSION wsrep_OSU_method=TOI;
```

### Non-Blocking Operations (NBO)

Available for certain DDL operations (e.g., index creation). Reduces blocking impact.

```sql
SET SESSION wsrep_OSU_method=NBO;
ALTER TABLE my_table ADD INDEX idx_col (col_name);
SET SESSION wsrep_OSU_method=TOI;
```

---

## Common Issues and Troubleshooting

### Split-Brain Detection

Split-brain occurs when the cluster loses quorum (less than half + 1 nodes reachable).

```sql
-- Check cluster status
SHOW STATUS LIKE 'wsrep_cluster_status';
-- If "Non-Primary", the node has lost quorum

-- Check cluster size
SHOW STATUS LIKE 'wsrep_cluster_size';

-- Check connectivity
SHOW STATUS LIKE 'wsrep_connected';
```

**Resolution:**

```sql
-- If you're certain this partition has the latest data:
SET GLOBAL wsrep_provider_options='pc.bootstrap=YES';
```

**Warning**: Only use `pc.bootstrap=YES` on the partition with the most current data. Using it on a stale partition causes data loss.

### Donor/Desynced Node Issues

```sql
-- Check if node is acting as donor
SHOW STATUS LIKE 'wsrep_local_state_comment';   -- "Donor/Desynced"

-- Monitor SST progress
SHOW STATUS LIKE 'wsrep_local_state_uuid';       -- Should match cluster UUID
SHOW STATUS LIKE 'wsrep_local_recv_queue';        -- Queue size during donor state
```

**Prevention:**
- Size `gcache.size` large enough for IST to avoid full SST
- Set `gcs.sync_donor=NO` (default) so donor does not block the cluster

### SST Failures

Common causes and fixes:
- **Missing datadir in my.cnf**: Ensure `datadir=/var/lib/mysql` is explicitly set
- **Empty socket variable**: The `socket` variable cannot be empty
- **Disk space**: Joiner needs enough space for the full dataset
- **Network timeout**: Increase `sst_idle_timeout` for large datasets
- **Permissions**: XtraBackup needs appropriate MySQL privileges

```ini
# Increase SST timeout for large datasets
sst_idle_timeout=600
```

### Node Not Joining / Stuck in Joining State

```sql
-- Check wsrep status on the stuck node
SHOW STATUS LIKE 'wsrep%';

-- Verify cluster name matches
SHOW VARIABLES LIKE 'wsrep_cluster_name';

-- Check for GComm connectivity
SHOW STATUS LIKE 'wsrep_connected';

-- Verify the IST/SST state
SHOW STATUS LIKE 'wsrep_local_state_comment';
```

**Common fixes:**
- Verify `wsrep_cluster_name` matches on all nodes
- Check firewall rules for ports 4567 (cluster), 4568 (IST), 4444 (SST)
- Ensure `wsrep_cluster_address` is correct on all nodes
- Check available disk space

### Certification Conflicts (Deadlocks)

```sql
-- Monitor certification failures
SHOW STATUS LIKE 'wsrep_local_cert_failures';   -- Total certification failures
SHOW STATUS LIKE 'wsrep_local_bf_aborts';       -- Brute-force aborts (conflicts)
```

**Reducing conflicts:**
- Minimize multi-row updates across nodes simultaneously
- Use application-level conflict retry logic
- Increase `wsrep_retry_autocommit` (default: 1)
- Consider directing writes to a single node
- Use shorter transactions

### Full Cluster Health Check

```sql
-- Essential status variables to check
SHOW STATUS LIKE 'wsrep_cluster_size';            -- Expected node count
SHOW STATUS LIKE 'wsrep_cluster_status';          -- "Primary"
SHOW STATUS LIKE 'wsrep_connected';               -- "ON"
SHOW STATUS LIKE 'wsrep_ready';                   -- "ON"
SHOW STATUS LIKE 'wsrep_local_state_comment';     -- "Synced"
SHOW STATUS LIKE 'wsrep_local_recv_queue_avg';    -- Close to 0
SHOW STATUS LIKE 'wsrep_local_send_queue_avg';    -- Close to 0
SHOW STATUS LIKE 'wsrep_flow_control_paused';     -- Close to 0.0
SHOW STATUS LIKE 'wsrep_cert_deps_distance';      -- Parallelism potential
SHOW STATUS LIKE 'wsrep_local_cert_failures';     -- Certification conflicts
SHOW STATUS LIKE 'wsrep_last_committed';          -- Latest committed seqno
```

### Firewall / Network Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 3306 | TCP | MySQL client connections |
| 4567 | TCP/UDP | Galera cluster communication (GComm) |
| 4568 | TCP | Incremental State Transfer (IST) |
| 4444 | TCP | State Snapshot Transfer (SST) |

```bash
# Verify connectivity between nodes
nc -zv 192.168.0.2 4567
nc -zv 192.168.0.2 4568
nc -zv 192.168.0.2 4444
```

---

## Limitations and Constraints

- **InnoDB only**: Only InnoDB tables are replicated. MyISAM replication is experimental (`wsrep_replicate_myisam=ON`).
- **Primary keys required**: All tables should have primary keys for efficient certification and parallel applying.
- **LOCK TABLES**: Not supported in `ENFORCING` strict mode; causes issues with multi-master writes.
- **XA transactions**: Not supported with Galera replication.
- **Large transactions**: Transactions larger than `wsrep_max_ws_size` (default 2 GB) will be rejected. Use streaming replication for large batches.
- **Query log tables**: `general_log` and `slow_log` tables must use FILE format, not TABLE.
- **CREATE TABLE ... AS SELECT**: Not supported in TOI mode.
- **Cluster-wide DDL locking**: TOI DDL blocks the entire cluster. Plan schema changes during low-traffic periods or use RSU/NBO.
