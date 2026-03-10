---
name: pxc-operator
description: "Percona Operator for MySQL (PXC) - Kubernetes operator for deploying, managing, and scaling Percona XtraDB Cluster with automated failover, backups, and monitoring."
metadata:
  languages: "yaml,bash"
  versions: "1.19.0"
  revision: 1
  updated-on: "2026-03-09"
  source: community
  tags: "percona,pxc,mysql,kubernetes,operator,galera,high-availability,database"
---

# Percona Operator for MySQL (PXC) on Kubernetes - Operations Guide

You are a Percona Operator for MySQL expert. Help me deploy, manage, and troubleshoot Percona XtraDB Cluster on Kubernetes using the Percona Operator.

## Golden Rule: Use the Official Percona Operator

Always use the official Percona Operator for MySQL based on Percona XtraDB Cluster for Kubernetes-native MySQL high availability.

- **Operator Version:** 1.19.0
- **Helm Chart (Operator):** `percona/pxc-operator`
- **Helm Chart (Database):** `percona/pxc-db`
- **GitHub:** https://github.com/percona/percona-xtradb-cluster-operator
- **CRD Kind:** `PerconaXtraDBCluster` (shortname: `pxc`)

**Supported PXC Versions:**
- Percona XtraDB Cluster 8.4.7-7.1 (Tech Preview)
- Percona XtraDB Cluster 8.0.44-35.1
- Percona XtraDB Cluster 5.7.44-31.65

**Supported Kubernetes Platforms (Operator 1.19.0):**

| Platform | Versions |
|----------|----------|
| Google Kubernetes Engine (GKE) | 1.31 - 1.33 |
| Amazon EKS | 1.32 - 1.34 |
| Azure Kubernetes Service (AKS) | 1.32 - 1.34 |
| OpenShift | 4.17 - 4.20 |
| Minikube | 1.37.0 (Kubernetes 1.34.0) |

**Minimum Resource Requirements (per node):**
- 3 Kubernetes nodes minimum
- 2 GB RAM per node
- 2 CPU threads per node
- 60 GB+ available storage for PVCs

---

## Architecture Overview

The Percona Operator manages the full lifecycle of a Percona XtraDB Cluster on Kubernetes:

- **Operator Controller**: Watches `PerconaXtraDBCluster` CRs and reconciles desired state
- **PXC Nodes**: StatefulSet of Percona XtraDB Cluster instances with synchronous Galera replication
- **Proxy Layer**: HAProxy (default) or ProxySQL for load balancing and read/write splitting
- **Backup Infrastructure**: Percona XtraBackup-based backup/restore to S3, GCS, Azure, or PVCs
- **Monitoring**: PMM (Percona Monitoring and Management) sidecar containers
- **TLS**: Automatic certificate management via cert-manager or manual secrets

---

## Installation

### Method 1: Helm (Recommended)

**Prerequisites:** Helm v3, kubectl

```bash
# Add Percona Helm repository
helm repo add percona https://percona.github.io/percona-helm-charts/
helm repo update

# Create namespace
kubectl create namespace pxc

# Install the Operator
helm install my-op percona/pxc-operator --namespace pxc

# Deploy Percona XtraDB Cluster
helm install my-db percona/pxc-db --namespace pxc

# Verify deployment
kubectl get pxc -n pxc
```

The default Helm deployment creates 3 HAProxy instances and 3 XtraDB Cluster instances.

**Customizing Helm values:**

```bash
# Install with custom values
helm install my-db percona/pxc-db --namespace pxc \
  --set pxc.size=5 \
  --set pxc.resources.requests.memory=4G \
  --set pxc.resources.requests.cpu=2 \
  --set backup.enabled=true

# Or use a values file
helm install my-db percona/pxc-db --namespace pxc -f my-values.yaml
```

Chart source references:
- Operator chart: https://github.com/percona/percona-helm-charts/tree/main/charts/pxc-operator
- Database chart: https://github.com/percona/percona-helm-charts/tree/main/charts/pxc-db

### Method 2: kubectl

```bash
# Create namespace
kubectl create namespace pxc

# Deploy Operator (includes CRDs, RBAC, and Operator deployment)
kubectl apply --server-side \
  -f https://raw.githubusercontent.com/percona/percona-xtradb-cluster-operator/v1.19.0/deploy/bundle.yaml \
  -n pxc

# Deploy the PXC cluster Custom Resource
kubectl apply \
  -f https://raw.githubusercontent.com/percona/percona-xtradb-cluster-operator/v1.19.0/deploy/cr.yaml \
  -n pxc

# Verify deployment
kubectl get pxc -n pxc
```

The `bundle.yaml` includes:
- Custom Resource Definitions (CRDs) for clusters, backups, and restores
- RBAC roles and service account configuration
- Operator Deployment manifest

### Verifying the Cluster

```bash
# Check cluster status
kubectl get pxc -n pxc

# Check all pods
kubectl get pods -n pxc

# Check services
kubectl get svc -n pxc
```

A healthy cluster shows `ready` status with all pods in `Running` state and all containers ready (e.g., `3/3`).

### Connecting to MySQL

```bash
# Get the root password from the secret
kubectl get secret my-db-pxc-db-secrets -n pxc -o jsonpath='{.data.root}' | base64 -d

# Connect via the HAProxy service
kubectl run -i --rm --tty percona-client --image=percona:8.0 --restart=Never -- \
  mysql -h my-db-pxc-db-haproxy -uroot -p<password>
```

---

## Custom Resource (PerconaXtraDBCluster) Specification

### Complete CR Example

```yaml
apiVersion: pxc.percona.com/v1
kind: PerconaXtraDBCluster
metadata:
  name: my-cluster
  finalizers:
    - percona.com/delete-pods-in-order
    # Optional: delete PVCs on cluster deletion
    # - percona.com/delete-pxc-pvc
    # - percona.com/delete-proxysql-pvc
    # - percona.com/delete-ssl
spec:
  crVersion: "1.19.0"
  secretsName: my-cluster-secrets
  enableCRValidationWebhook: true
  enableVolumeExpansion: true
  pause: false
  updateStrategy: SmartUpdate

  unsafeFlags:
    tls: false
    pxcSize: false
    proxySize: false
    backupIfUnhealthy: false

  upgradeOptions:
    versionServiceEndpoint: "https://check.percona.com"
    apply: "Recommended"
    schedule: "0 2 * * *"

  tls:
    enabled: true
    certValidityDuration: "2160h"
    caValidityDuration: "26280h"
    SANs: []
    issuerConf:
      name: "selfsigned-issuer"
      kind: "Issuer"
      group: "cert-manager.io"

  pxc:
    size: 3
    image: "percona/percona-xtradb-cluster:8.0.44-35.1"
    autoRecovery: true
    imagePullPolicy: IfNotPresent
    resources:
      requests:
        memory: "2G"
        cpu: "1000m"
      limits:
        memory: "4G"
        cpu: "2000m"
    volumeSpec:
      persistentVolumeClaim:
        storageClassName: "fast-ssd"
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 100Gi
    affinity:
      topologyKey: "kubernetes.io/hostname"
    tolerations:
      - key: "dedicated"
        operator: "Equal"
        value: "database"
        effect: "NoSchedule"
    podDisruptionBudget:
      maxUnavailable: 1
    gracePeriod: 600
    configuration: |
      [mysqld]
      wsrep_debug=OFF
      wsrep_provider_options="gcache.size=1G;gcache.recover=yes"
    readinessProbes:
      initialDelaySeconds: 15
      timeoutSeconds: 15
      periodSeconds: 10
      successThreshold: 1
      failureThreshold: 5
    livenessProbes:
      initialDelaySeconds: 300
      timeoutSeconds: 5
      periodSeconds: 10
      successThreshold: 1
      failureThreshold: 3

  haproxy:
    enabled: true
    size: 3
    image: "percona/percona-xtradb-cluster-operator:1.19.0"
    imagePullPolicy: IfNotPresent
    resources:
      requests:
        memory: "256Mi"
        cpu: "100m"
      limits:
        memory: "512Mi"
        cpu: "500m"
    affinity:
      topologyKey: "kubernetes.io/hostname"
    exposePrimary:
      enabled: true
      type: LoadBalancer
      externalTrafficPolicy: Local
      annotations: {}
      labels: {}
    exposeReplicas:
      enabled: true
      onlyReaders: false
      type: LoadBalancer
      externalTrafficPolicy: Cluster
    healthCheck:
      interval: 5000
      fall: 3
      rise: 2
    readinessProbes:
      initialDelaySeconds: 15
      timeoutSeconds: 5
      periodSeconds: 10
    livenessProbes:
      initialDelaySeconds: 60
      timeoutSeconds: 5
      periodSeconds: 10
    podDisruptionBudget:
      maxUnavailable: 1
    gracePeriod: 300

  proxysql:
    enabled: false
    size: 3
    image: "percona/percona-xtradb-cluster-operator:1.19.0"
    resources:
      requests:
        memory: "256Mi"
        cpu: "100m"
      limits:
        memory: "512Mi"
        cpu: "500m"
    volumeSpec:
      persistentVolumeClaim:
        storageClassName: "standard"
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 2Gi
    scheduler:
      enabled: true
      writerIsAlsoReader: false
      checkTimeoutMilliseconds: 800
      successThreshold: 2
      failureThreshold: 3
      pingTimeoutMilliseconds: 500
      nodeCheckIntervalMilliseconds: 5000
      maxConnections: 500

  pmm:
    enabled: false
    image: "percona/pmm-client:2.44.1-1"
    serverHost: "pmm-server.monitoring"
    serverUser: "pmm"
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
      limits:
        memory: "128Mi"
        cpu: "500m"
    pxcParams: "--max-query-length=1000"
    proxysqlParams: "--max-query-length=1000"

  logcollector:
    enabled: true
    image: "percona/percona-xtradb-cluster-operator:1.19.0"
    resources:
      requests:
        memory: "128Mi"
        cpu: "100m"
      limits:
        memory: "256Mi"
        cpu: "500m"

  backup:
    image: "percona/percona-xtradb-cluster-operator:1.19.0"
    allowParallel: true
    ttlSecondsAfterFinished: 259200
    backoffLimit: 3
    storages:
      s3-us-east:
        type: s3
        verifyTLS: true
        s3:
          bucket: my-pxc-backups
          region: us-east-1
          credentialsSecret: aws-s3-credentials
          endpointUrl: "https://s3.amazonaws.com"
      pvc-backup:
        type: volume
        volume:
          persistentVolumeClaim:
            storageClassName: standard
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 100Gi
    schedule:
      - name: daily-s3-backup
        schedule: "0 2 * * *"
        keep: 7
        storageName: s3-us-east
      - name: weekly-pvc-backup
        schedule: "0 3 * * 0"
        keep: 4
        storageName: pvc-backup
    pitr:
      enabled: true
      storageName: s3-us-east
      timeBetweenUploads: 60
      timeoutSeconds: 600
```

### Metadata and Finalizers

| Field | Description |
|-------|-------------|
| `metadata.name` | Cluster name (max 22 chars, URL-safe, starts alphabetic, ends alphanumeric) |
| `finalizers: percona.com/delete-pods-in-order` | Manages proper Pod deletion sequence (default: enabled) |
| `finalizers: percona.com/delete-pxc-pvc` | Removes PVCs after cluster deletion (default: disabled) |
| `finalizers: percona.com/delete-proxysql-pvc` | Removes ProxySQL PVCs (default: disabled) |
| `finalizers: percona.com/delete-ssl` | Removes TLS certs and related objects (default: disabled) |

### Top-Level Spec Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `crVersion` | string | `"1.19.0"` | Operator version this CR targets |
| `secretsName` | string | `cluster1-secrets` | Name of Secret with user credentials |
| `enableCRValidationWebhook` | boolean | `true` | Enable schema validation before applying CR |
| `enableVolumeExpansion` | boolean | `false` | Allow automatic PVC expansion |
| `pause` | boolean | `false` | Gracefully stop/start the cluster |
| `updateStrategy` | string | `SmartUpdate` | Upgrade approach: SmartUpdate, RollingUpdate, OnDelete |
| `sslSecretName` | string | - | TLS certificate for external communications |
| `sslInternalSecretName` | string | - | TLS certificate for internal communications |
| `vaultSecretName` | string | - | HashiCorp Vault secret for data-at-rest encryption |
| `logCollectorSecretName` | string | - | Fluent Bit log collector credentials |
| `ignoreAnnotations` | list | `[]` | Annotations the Operator should ignore |
| `ignoreLabels` | list | `[]` | Labels the Operator should ignore |

### Unsafe Flags (spec.unsafeFlags)

| Flag | Type | Effect When True |
|------|------|------------------|
| `tls` | boolean | Allows cluster without TLS/SSL (NOT for production) |
| `pxcSize` | boolean | Permits unsafe node counts: <3, >5, or even numbers |
| `proxySize` | boolean | Allows <2 proxy pods |
| `backupIfUnhealthy` | boolean | Enables backups despite cluster status != ready |

**Warning**: Unsafe configurations risk availability loss, split-brain, or performance degradation.

---

## PXC Node Configuration (spec.pxc)

### Key Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `size` | int | `3` | Number of PXC nodes (3 or 5 recommended) |
| `image` | string | - | PXC container image |
| `autoRecovery` | boolean | `true` | Enable crash recovery |
| `configuration` | string | - | Custom my.cnf content for `[mysqld]` section |
| `mysqlAllocator` | string | - | Memory allocator (e.g., `jemalloc`) |
| `envVarsSecret` | string | - | Secret with environment variables for PXC pods |

### Exposure/Networking (spec.pxc.expose)

```yaml
pxc:
  expose:
    enabled: true
    type: LoadBalancer         # ClusterIP, LoadBalancer, NodePort
    loadBalancerClass: "eks.amazonaws.com/nlb"
    externalTrafficPolicy: Local
    internalTrafficPolicy: Local
    loadBalancerSourceRanges:
      - "10.0.0.0/8"
    annotations:
      networking.gke.io/load-balancer-type: "Internal"
```

### Cross-Site Replication (spec.pxc.replicationChannels)

```yaml
pxc:
  replicationChannels:
    - name: "pxc1_to_pxc2"
      isSource: false
      configuration:
        sourceRetryCount: 3
        sourceConnectRetry: 60
        ssl: false
        sslSkipVerify: true
        ca: "/etc/mysql/ssl/ca.crt"
      sourcesList:
        - host: "10.95.251.101"
          port: 3306
          weight: 100
```

### Sidecars

```yaml
pxc:
  sidecars:
    - name: monitoring-agent
      image: agent:latest
      command: ["/bin/agent"]
      args: ["--config=/etc/agent.conf"]
      resources:
        requests:
          memory: "128Mi"
          cpu: "100m"
        limits:
          memory: "256Mi"
          cpu: "500m"
```

### Storage with Volume Snapshots

```yaml
pxc:
  volumeSpec:
    persistentVolumeClaim:
      storageClassName: "fast-ssd"
      accessModes:
        - ReadWriteOnce
      dataSource:
        name: "snapshot-source"
        kind: "VolumeSnapshot"
        apiGroup: "snapshot.storage.k8s.io"
  extraPVCs:
    - name: "backup-storage"
      claimName: "my-backup-pvc"
      mountPath: "/backups"
      subPath: "data"
      readOnly: false
```

### Pod Scheduling

```yaml
pxc:
  priorityClassName: "high-priority"
  schedulerName: "custom-scheduler"
  nodeSelector:
    disktype: "ssd"
  topologySpreadConstraints:
    - labelSelector:
        matchLabels:
          app: pxc
      maxSkew: 1
      topologyKey: "kubernetes.io/hostname"
      whenUnsatisfiable: DoNotSchedule
  affinity:
    topologyKey: "kubernetes.io/hostname"
  tolerations:
    - key: "dedicated"
      operator: "Equal"
      value: "database"
      effect: "NoSchedule"
  containerSecurityContext:
    runAsUser: 1001
    runAsGroup: 1001
    privileged: false
  podSecurityContext:
    fsGroup: 1001
```

### Lifecycle Hooks and PDB

```yaml
pxc:
  podDisruptionBudget:
    maxUnavailable: 1
    minAvailable: 2
  gracePeriod: 600
  lifecycle:
    preStop:
      exec:
        command: ["/bin/sh", "-c", "sleep 30"]
    postStart:
      exec:
        command: ["/bin/sh", "-c", "echo started"]
```

---

## HAProxy Configuration (spec.haproxy)

Use HAProxy (default) for TCP-level load balancing. Enable either HAProxy or ProxySQL, not both.

### Service Exposure

```yaml
haproxy:
  enabled: true
  size: 3
  serviceType: LoadBalancer
  externalTrafficPolicy: Local
  exposePrimary:
    enabled: true
    type: LoadBalancer
    loadBalancerClass: "aws-nlb"
    externalTrafficPolicy: Local
    internalTrafficPolicy: Cluster
    loadBalancerSourceRanges:
      - "10.0.0.0/8"
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    labels:
      tier: primary
  exposeReplicas:
    enabled: true
    onlyReaders: false
    type: LoadBalancer
    externalTrafficPolicy: Cluster
    labels:
      tier: replica
```

### Custom HAProxy Configuration

```yaml
haproxy:
  configuration: |
    global
      maxconn 4096
    defaults
      mode tcp
      timeout connect 5000
      timeout client 28800
      timeout server 28800
```

### Health Checks

```yaml
haproxy:
  healthCheck:
    interval: 5000       # milliseconds between checks
    fall: 3              # failed checks before marking down
    rise: 2              # successful checks before marking up
```

---

## ProxySQL Configuration (spec.proxysql)

Use ProxySQL for query-level routing and read/write splitting.

```yaml
proxysql:
  enabled: true      # Disable haproxy when enabling proxysql
  size: 3
  expose:
    enabled: true
    type: LoadBalancer
  scheduler:
    enabled: true
    writerIsAlsoReader: false
    checkTimeoutMilliseconds: 800
    successThreshold: 2
    failureThreshold: 3
    pingTimeoutMilliseconds: 500
    nodeCheckIntervalMilliseconds: 5000
    maxConnections: 500
  configuration: |
    [admin_variables]
    admin_credentials="admin:admin;radmin:radmin"
    mysql_ifaces="0.0.0.0:6032"
```

---

## Backup and Restore

### Backup Storage Types

**S3-compatible storage:**

```yaml
backup:
  storages:
    s3-backup:
      type: s3
      verifyTLS: true
      s3:
        bucket: my-pxc-backups
        region: us-east-1
        credentialsSecret: aws-s3-credentials
        endpointUrl: "https://s3.amazonaws.com"
```

**S3 credentials secret:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: aws-s3-credentials
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: "AKIAIOSFODNN7EXAMPLE"
  AWS_SECRET_ACCESS_KEY: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
```

**Azure Blob Storage:**

```yaml
backup:
  storages:
    azure-backup:
      type: azure
      azure:
        credentialsSecret: azure-credentials
        container: my-pxc-backups
        endpointUrl: "https://myaccount.blob.core.windows.net"
```

**Persistent Volume (on-prem):**

```yaml
backup:
  storages:
    pvc-backup:
      type: volume
      volume:
        persistentVolumeClaim:
          storageClassName: standard
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 100Gi
```

### Scheduled Backups

```yaml
backup:
  schedule:
    - name: daily-backup
      schedule: "0 2 * * *"       # Cron: daily at 2 AM
      keep: 7                      # Retain 7 backups
      storageName: s3-backup
      retention:
        type: count
        count: 10
        deleteFromStorage: true
    - name: hourly-backup
      schedule: "0 * * * *"
      keep: 24
      storageName: s3-backup
```

### On-Demand Backup

```yaml
apiVersion: pxc.percona.com/v1
kind: PerconaXtraDBClusterBackup
metadata:
  name: my-backup-$(date +%Y%m%d%H%M%S)
spec:
  pxcCluster: my-cluster
  storageName: s3-backup
```

```bash
# Create on-demand backup
kubectl apply -f backup.yaml -n pxc

# Check backup status
kubectl get pxc-backup -n pxc
```

### Point-in-Time Recovery (PITR)

```yaml
backup:
  pitr:
    enabled: true
    storageName: s3-backup
    timeBetweenUploads: 60       # Upload binlogs every 60 seconds
    timeoutSeconds: 600
    resources:
      requests:
        memory: "512Mi"
        cpu: "200m"
```

### Restore from Backup

```yaml
apiVersion: pxc.percona.com/v1
kind: PerconaXtraDBClusterRestore
metadata:
  name: my-restore
spec:
  pxcCluster: my-cluster
  backupName: daily-backup-20260309
```

```bash
# Initiate restore
kubectl apply -f restore.yaml -n pxc

# Monitor restore progress
kubectl get pxc-restore -n pxc
```

### PITR Restore to Specific Time

```yaml
apiVersion: pxc.percona.com/v1
kind: PerconaXtraDBClusterRestore
metadata:
  name: my-pitr-restore
spec:
  pxcCluster: my-cluster
  backupName: daily-backup-20260309
  pitr:
    type: date
    date: "2026-03-09 14:30:00"
    storageName: s3-backup
```

### Backup Advanced Options

```yaml
backup:
  allowParallel: true                  # Multiple backups simultaneously
  ttlSecondsAfterFinished: 259200     # Auto-cleanup after 3 days
  backoffLimit: 3                      # Retry count
  activeDeadlineSeconds: 3600          # Max backup duration
  startingDeadlineSeconds: 0           # Startup wait time
  suspendedDeadlineSeconds: 0          # Suspension timeout
  storages:
    s3-backup:
      containerOptions:
        args:
          xtrabackup: ["--compress=QUICKLZ"]
          xbcloud: ["--parallel=4"]
          xbstream: ["--extract"]
```

---

## Scaling

### Horizontal Scaling

```bash
# Scale PXC nodes via CR edit
kubectl patch pxc my-cluster --type=merge -p '{"spec":{"pxc":{"size":5}}}' -n pxc

# Or scale directly
kubectl scale --replicas=5 pxc/my-cluster -n pxc
```

```yaml
# In the CR
spec:
  pxc:
    size: 5    # Scale from 3 to 5 nodes
  haproxy:
    size: 3    # Scale proxy independently
```

### Vertical Scaling

```yaml
spec:
  pxc:
    resources:
      requests:
        memory: 4G
        cpu: 2
      limits:
        memory: 8G
        cpu: 4
```

Apply changes:

```bash
kubectl apply -f deploy/cr.yaml -n pxc
```

### Storage Scaling (PVC Expansion)

```yaml
spec:
  enableVolumeExpansion: true
  pxc:
    volumeSpec:
      persistentVolumeClaim:
        resources:
          requests:
            storage: 200Gi    # Increase from 100Gi
```

Verify storage class supports expansion:

```bash
kubectl describe sc <storage-class> | grep AllowVolumeExpansion
```

**Manual storage expansion (older versions):**

```bash
# 1. Update the CR with new storage size
# 2. Delete StatefulSet with orphan cascade
kubectl delete sts <name> --cascade=orphan -n pxc
# 3. Delete PVCs and Pods sequentially, allowing data resync
```

### Autoscaling with KEDA

Kubernetes Event-driven Autoscaling (KEDA) is supported for more sophisticated scaling logic. Note: Vertical Pod Autoscaler (VPA) is not compatible due to owner reference limitations.

---

## Upgrading

### Update Strategies

| Strategy | Description |
|----------|-------------|
| `SmartUpdate` | (Recommended) Operator-controlled; restarts pods in optimal order, primary last |
| `RollingUpdate` | Kubernetes StatefulSet controller manages; one pod at a time, may not follow optimal order |
| `OnDelete` | Manual; user deletes pods, StatefulSet recreates with updated config |

### Automatic Upgrades

```yaml
spec:
  updateStrategy: SmartUpdate
  upgradeOptions:
    versionServiceEndpoint: "https://check.percona.com"
    apply: "Recommended"       # Never, Disabled, Latest, Recommended, or specific version
    schedule: "0 2 * * *"      # Check for updates daily at 2 AM
```

### Manual Operator Upgrade (Helm)

```bash
# Update Helm repos
helm repo update

# Upgrade the Operator
helm upgrade my-op percona/pxc-operator --namespace pxc

# Update crVersion in your CR
# Then apply the updated CR
kubectl apply -f deploy/cr.yaml -n pxc
```

### Manual Operator Upgrade (kubectl)

```bash
# Apply new bundle
kubectl apply --server-side \
  -f https://raw.githubusercontent.com/percona/percona-xtradb-cluster-operator/v1.19.0/deploy/bundle.yaml \
  -n pxc
```

### Database Version Upgrade

Update the image tag in the CR:

```yaml
spec:
  pxc:
    image: "percona/percona-xtradb-cluster:8.0.44-35.1"
```

```bash
kubectl apply -f deploy/cr.yaml -n pxc
```

---

## TLS/SSL Configuration

### Automatic TLS (Default)

The Operator automatically generates long-term self-signed certificates during cluster creation if no certificate secrets exist.

### TLS with cert-manager

```yaml
spec:
  tls:
    enabled: true
    certValidityDuration: "2160h"        # 90 days
    caValidityDuration: "26280h"         # 3 years (min 730h)
    SANs: []                             # Additional SANs
    issuerConf:
      name: "selfsigned-issuer"
      kind: "ClusterIssuer"
      group: "cert-manager.io"
```

### Manual TLS Certificates

Provide certificates via Kubernetes Secrets:

```yaml
spec:
  sslSecretName: "my-cluster-ssl"               # External TLS
  sslInternalSecretName: "my-cluster-ssl-internal"  # Internal TLS
```

```bash
# Create external TLS secret
kubectl create secret generic my-cluster-ssl \
  --from-file=tls.crt=server.crt \
  --from-file=tls.key=server.key \
  --from-file=ca.crt=ca.crt \
  -n pxc

# Create internal TLS secret
kubectl create secret generic my-cluster-ssl-internal \
  --from-file=tls.crt=internal.crt \
  --from-file=tls.key=internal.key \
  --from-file=ca.crt=ca.crt \
  -n pxc
```

**Important**: Do NOT use the pre-generated test certificates from `deploy/ssl-secrets.yaml` in production.

### Disabling TLS (Not Recommended)

```yaml
spec:
  unsafeFlags:
    tls: true    # WARNING: Not for production use
```

---

## Monitoring with PMM

### PMM 3 Setup (Recommended)

```yaml
spec:
  pmm:
    enabled: true
    image: "percona/pmm-client:2.44.1-1"
    serverHost: pmm-server.monitoring
    customClusterName: "my-pxc-cluster"
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
      limits:
        memory: "128Mi"
        cpu: "500m"
    pxcParams: "--max-query-length=1000"
    proxysqlParams: "--max-query-length=1000"
```

**PMM3 authentication (Grafana service account token):**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-cluster-secrets
type: Opaque
stringData:
  pmmservertoken: "<grafana-service-account-token>"
```

**PMM2 authentication (API key):**

```bash
# Get API key from PMM Server
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"name":"pxc-operator","role":"Admin"}' \
  https://admin:password@pmm-server/graph/api/auth/keys
```

**Updating PMM token:**

```bash
kubectl patch secret/my-cluster-secrets -p \
  '{"data":{"pmmservertoken": "'$(echo -n <new-token> | base64 --wrap=0)'"}}' \
  -n pxc
```

PMM deploys sidecar containers in PXC, HAProxy, and ProxySQL pods to collect metrics.

---

## Log Collection

```yaml
spec:
  logcollector:
    enabled: true
    image: "percona/percona-xtradb-cluster-operator:1.19.0"
    configuration: |
      [INPUT]
        Name tail
        Path /var/log/mysql/*.log
        Tag mysql.*
      [OUTPUT]
        Name stdout
    resources:
      requests:
        memory: "128Mi"
        cpu: "100m"
      limits:
        memory: "256Mi"
        cpu: "500m"
```

---

## Users Management

```yaml
spec:
  users:
    - name: "appuser"
      dbs: ["myapp", "test"]
      hosts: ["%", "localhost"]
      passwordSecretRef:
        name: "app-password-secret"
        key: "password"
      withGrantOption: true
      grants:
        - "SELECT,INSERT,UPDATE,DELETE"
        - "CREATE TEMPORARY TABLES"
```

---

## Init Container Customization

```yaml
spec:
  initContainer:
    image: "percona/percona-xtradb-cluster-operator:1.19.0"
    containerSecurityContext:
      privileged: false
      runAsUser: 1001
      runAsGroup: 1001
    resources:
      requests:
        memory: "1G"
        cpu: "600m"
      limits:
        memory: "1G"
        cpu: "1"
```

---

## Password Generation

```yaml
spec:
  passwordGenerationOptions:
    symbols: "!#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
    minLength: 16
    maxLength: 32
```

---

## Troubleshooting

### Check Custom Resource Status

```bash
# Get cluster status
kubectl get pxc -n pxc

# View all Percona CRs
kubectl api-resources | grep -i percona

# Detailed cluster info
kubectl describe pxc my-cluster -n pxc
```

### Inspect Pods

```bash
# List all pods
kubectl get pods -n pxc

# Detailed pod info (shows events, probes, resource limits)
kubectl describe pod <pod-name> -n pxc

# PXC node logs
kubectl logs <pxc-pod-name> -c pxc -n pxc

# HAProxy logs
kubectl logs <haproxy-pod-name> -c haproxy -n pxc

# Operator logs
kubectl logs deployment/percona-xtradb-cluster-operator -n pxc
```

### Check Backup and Restore Status

```bash
# List backups
kubectl get pxc-backup -n pxc

# List restores
kubectl get pxc-restore -n pxc

# Describe specific backup
kubectl describe pxc-backup <backup-name> -n pxc
```

### Healthy Cluster Indicators

- All pods show `Running` status with all containers ready (e.g., `3/3`)
- Zero or low restart counts
- `kubectl get pxc` shows `ready` status
- Cluster endpoint is populated

### Common Issues

| Symptom | Possible Cause | Resolution |
|---------|---------------|------------|
| Pod in CrashLoopBackOff | Resource limits too low, config error | Check logs, increase resources |
| Cluster status not `ready` | Nodes not syncing | Check wsrep status, verify network |
| Backup failing | Storage credentials invalid | Verify secret, test connectivity |
| PVC stuck in Pending | StorageClass unavailable | Check storage provisioner |
| TLS errors | Certificate expired or misconfigured | Regenerate certs, check secrets |
| High restart count | Liveness probe timeout | Increase `initialDelaySeconds` |

### MySQL Cluster Health Inside Pod

```bash
# Connect to a PXC pod
kubectl exec -it <pxc-pod> -c pxc -n pxc -- mysql -uroot -p

# Check wsrep status
mysql> SHOW STATUS LIKE 'wsrep%';

# Key variables to check
mysql> SHOW STATUS LIKE 'wsrep_cluster_size';      -- Number of nodes
mysql> SHOW STATUS LIKE 'wsrep_cluster_status';     -- Should be "Primary"
mysql> SHOW STATUS LIKE 'wsrep_connected';           -- Should be "ON"
mysql> SHOW STATUS LIKE 'wsrep_ready';               -- Should be "ON"
mysql> SHOW STATUS LIKE 'wsrep_local_state_comment'; -- Should be "Synced"
```
