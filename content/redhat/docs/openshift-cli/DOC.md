---
name: openshift-cli
description: "OpenShift oc CLI - Complete guide for deploying and configuring applications on OpenShift Container Platform"
metadata:
  languages: "shell"
  versions: "4.18"
  revision: 1
  updated-on: "2026-03-09"
  source: community
  tags: "openshift,oc,kubernetes,deployment,cli,redhat,containers,cloud"
---

# OpenShift `oc` CLI - Deployment & Configuration Guide

## Golden Rule

**ALWAYS use the `oc` CLI for OpenShift-specific operations. Use `kubectl` only for vanilla Kubernetes resources that have no OpenShift equivalent.**

The `oc` CLI is a superset of `kubectl` with additional commands for OpenShift-specific resources (Routes, DeploymentConfigs, BuildConfigs, ImageStreams, Projects). Every `kubectl` command works with `oc`, but not vice versa.

**Use `Deployment` objects (not `DeploymentConfig`) unless you need a specific feature only provided by `DeploymentConfig`. `DeploymentConfig` is deprecated as of OpenShift 4.14+.**

---

## Installation

### macOS (Homebrew)

```bash
brew install openshift-cli
```

### Linux (Binary Download)

```bash
# Download from the OpenShift web console:
# Click "?" icon > "Command Line Tools" > "Download oc for Linux"
tar xvf <downloaded-file>
sudo mv oc /usr/local/bin/
```

### Linux (RPM - RHEL 8 only)

```bash
# Register and attach subscription
subscription-manager register
subscription-manager refresh
subscription-manager list --available --matches '*OpenShift*'
subscription-manager attach --pool=<pool_id>

# Enable repo and install
subscription-manager repos --enable="rhocp-4.18-for-rhel-8-x86_64-rpms"
yum install openshift-clients
```

> RPM installation is NOT supported on RHEL 9. Use binary download instead.

### Windows

Download the `oc.exe` binary from the OpenShift web console under "Command Line Tools" and add it to your PATH.

### Verify Installation

```bash
oc version
```

---

## Authentication & Login

### Interactive Login

```bash
oc login
# Prompts for: server URL, certificate confirmation, username, password
```

### Login with Credentials

```bash
oc login -u <username> -p <password> https://<cluster-api>:6443
```

### Token-Based Login

```bash
# Get token from web console: username menu > "Copy login command"
oc login --token=<token> --server=https://<cluster-api>:6443
```

### Proxy Configuration

The CLI respects `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY` environment variables. Auth headers are only transmitted over HTTPS.

### Logout and Identity

```bash
oc logout
oc whoami                    # show current user
oc whoami --show-server      # show cluster API URL
oc whoami --show-token       # show current auth token
```

---

## Projects (Namespaces)

```bash
oc new-project <name>                          # create a new project
oc new-project myapp --display-name="My App"   # with display name and description
oc project <name>                              # switch to a project
oc projects                                    # list all projects
oc status                                      # overview of current project
```

---

## Creating Applications

### From Container Image

```bash
oc new-app nginx
oc new-app mysql MYSQL_USER=admin MYSQL_PASSWORD=secret MYSQL_DATABASE=mydb
```

### From Source Code (S2I)

```bash
oc new-app https://github.com/sclorg/nodejs-ex.git
oc new-app python~https://github.com/user/repo.git   # specify builder image
```

### From Template

```bash
oc new-app --template=<template-name>
oc new-app --template=<template-name> -p PARAM1=value1 -p PARAM2=value2
```

### Run a Pod Directly

```bash
oc run my-pod --image=nginx --env="APP_ENV=production" --labels="app=web"
```

---

## Deployments

### Deployment vs DeploymentConfig

| Feature | Deployment | DeploymentConfig (Deprecated) |
|---------|------------|-------------------------------|
| API Group | `apps/v1` | `apps.openshift.io/v1` |
| Replica Management | ReplicaSets | ReplicationControllers |
| Failure Handling | Availability-first (HA controller manager with leader election) | Consistency-first (node-dependent, blocking) |
| Rollback | `oc rollout undo` | `oc rollout undo` |
| Triggers | Manual / external CI | Built-in ConfigChange & ImageChange triggers |
| Recommendation | **Preferred** | Use only if you need specific DC features |

### Creating a Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: my-registry/my-app:latest
        ports:
        - containerPort: 8080
```

```bash
oc apply -f deployment.yaml
```

### Rollout Management

```bash
oc rollout status deployment/my-app          # watch rollout progress
oc rollout history deployment/my-app         # list revision history
oc rollout history deployment/my-app --revision=2  # details of specific revision
oc rollout pause deployment/my-app           # pause rollout
oc rollout resume deployment/my-app          # resume rollout
oc rollout restart deployment/my-app         # trigger a new rollout
oc rollout undo deployment/my-app            # rollback to previous revision
oc rollout undo deployment/my-app --to-revision=3  # rollback to specific revision
```

### DeploymentConfig Rollout (Legacy)

```bash
oc rollout status dc/<name>
oc rollout history dc/<name>
oc rollout retry dc/<name>                   # retry a failed deployment
oc rollout undo dc/<name>                    # rollback
oc rollout undo dc/<name> --to-revision=1    # rollback to specific revision

# Re-enable image change triggers after rollback
oc set triggers dc/<name> --auto
```

### Describe Deployments

```bash
oc describe deployment my-app
oc describe dc <name>
```

---

## Deployment Strategies

### Rolling (Default)

Progressively replaces old pods with new ones. Zero downtime but requires N-1 compatibility (old and new code run simultaneously).

```yaml
apiVersion: apps.openshift.io/v1
kind: DeploymentConfig
metadata:
  name: example-dc
spec:
  strategy:
    type: Rolling
    rollingParams:
      updatePeriodSeconds: 1       # interval between pod updates (default: 1)
      intervalSeconds: 1           # polling frequency for status (default: 1)
      timeoutSeconds: 120          # timeout before rollback (default: 600)
      maxSurge: "20%"              # max pods over desired count (default: 25%)
      maxUnavailable: "10%"        # max unavailable pods (default: 25%)
      pre: {}                      # pre-deployment lifecycle hook
      post: {}                     # post-deployment lifecycle hook
```

**Execution sequence:**
1. Execute pre-deployment lifecycle hook
2. Scale up new ReplicationController based on `maxSurge`
3. Scale down old ReplicationController based on `maxUnavailable`
4. Repeat until new controller reaches desired replicas and old reaches zero
5. Execute post-deployment lifecycle hook

**Tuning examples:**
- `maxUnavailable=0, maxSurge=20%` -- full capacity maintained, rapid scale-up
- `maxUnavailable=10%, maxSurge=0` -- in-place update, no extra capacity needed
- `maxUnavailable=10%, maxSurge=10%` -- fast scaling with slight capacity reduction

For standard `Deployment` (recommended):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
```

### Recreate

Terminates all old pods before creating new ones. Causes brief downtime but ensures old and new code never run concurrently.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-openshift
spec:
  strategy:
    type: Recreate
    recreateParams:        # DeploymentConfig only
      pre: {}              # pre-hook
      mid: {}              # mid-hook (after scale down, before scale up)
      post: {}             # post-hook
```

**Execution sequence:**
1. Run `pre` lifecycle hook
2. Scale down previous deployment to zero
3. Run `mid` lifecycle hook
4. Scale up new deployment
5. Run `post` lifecycle hook

**Use when:**
- Data migrations must complete before new code starts
- Application cannot run old and new versions simultaneously
- Using RWO volumes (cannot be shared across replicas)

### Blue-Green

Run two identical environments. Switch traffic from blue (current) to green (new) via route updates.

```bash
# Deploy blue (v1) and green (v2) versions
oc new-app openshift/deployment-example:v1 --name=example-blue
oc new-app openshift/deployment-example:v2 --name=example-green

# Create route pointing to blue
oc expose svc/example-blue --name=bluegreen-example

# Switch traffic to green
oc patch route/bluegreen-example -p '{"spec":{"to":{"name":"example-green"}}}'

# Rollback: switch traffic back to blue
oc patch route/bluegreen-example -p '{"spec":{"to":{"name":"example-blue"}}}'
```

### Canary

All rolling deployments in OpenShift are canary deployments -- a new version is tested before all old instances are replaced. If the readiness check fails, the canary instance is removed and the deployment is automatically rolled back.

For more sophisticated canary testing, use A/B testing with route-based traffic splitting (see A/B Testing below).

### A/B Testing (Route-Based Traffic Splitting)

Split traffic between multiple services using weighted routes:

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: route-alternate-service
  annotations:
    haproxy.router.openshift.io/balance: roundrobin
spec:
  host: ab-example.my-project.my-domain
  to:
    kind: Service
    name: ab-example-a
    weight: 10
  alternateBackends:
  - kind: Service
    name: ab-example-b
    weight: 15
```

```bash
# Set traffic weights via CLI
oc set route-backends ab-example ab-example-a=198 ab-example-b=2
# Result: 99% to a, 1% to b

# View current weights
oc set route-backends ab-example

# Equal distribution
oc set route-backends ab-example --equal

# Zero out all backends (returns 503)
oc set route-backends ab-example --zero

# Adjust by percentage
oc set route-backends ab-example --adjust ab-example-b=5%

# Relative percentage adjustment
oc set route-backends ab-example --adjust ab-example-b=+15%
```

> When using `alternateBackends`, use the `roundrobin` load balancing strategy. Weights range 0-256. Weight 0 stops new traffic but preserves existing connections.

### Custom Strategy

Define your own deployment logic with a custom deployer image:

```yaml
strategy:
  type: Custom
  customParams:
    image: organization/strategy
    command: [ "command", "arg1" ]
    environment:
      - name: ENV_1
        value: VALUE_1
```

Environment variables automatically provided: `OPENSHIFT_DEPLOYMENT_NAME`, `OPENSHIFT_DEPLOYMENT_NAMESPACE`.

---

## Lifecycle Hooks

Available on Rolling and Recreate strategies. Pod-based hooks are the only supported type.

```bash
# Set a pre-deployment hook
oc set deployment-hook dc/frontend \
    --pre -c helloworld -e CUSTOM_VAR1=custom_value1 \
    --volumes data --failure-policy=abort -- /usr/bin/command arg1 arg2
```

**Failure policies:**
- `Abort` -- deployment fails if hook fails
- `Retry` -- hook retries until success
- `Ignore` -- hook failure is ignored, deployment proceeds

**Hook configuration fields:**
- `containerName` -- which container image to use
- `command` -- overrides the image ENTRYPOINT
- `env` -- optional environment variables
- `volumes` -- optional volume references

---

## Services & Routes

### Create a Service

```bash
oc expose deployment/my-app --port=8080
# Or via YAML
oc create -f service.yaml
```

### Expose a Service as a Route (HTTP)

```bash
oc expose svc/my-app
# Creates route: my-app-<project>.<router-domain>
```

### Verify Route

```bash
oc get route
# NAME     HOST/PORT                         PATH  SERVICES  PORT      TERMINATION  WILDCARD
# my-app   my-app-myproject.apps.example.com       my-app    8080-tcp               None

curl --head my-app-myproject.apps.example.com
```

### Route YAML

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: my-app
spec:
  host: www.example.com
  port:
    targetPort: 8080
  to:
    kind: Service
    name: my-app
```

### Secure Routes (TLS)

```bash
# Edge termination (TLS terminated at router)
oc create route edge --service=my-app --cert=tls.crt --key=tls.key

# Passthrough (TLS terminated at pod)
oc create route passthrough --service=my-app

# Re-encrypt (TLS terminated at router, re-encrypted to pod)
oc create route reencrypt --service=my-app --cert=tls.crt --key=tls.key --dest-ca-cert=dest-ca.crt
```

### Route Annotations

```bash
# Load balancing algorithm (random, source, roundrobin, leastconn)
oc annotate route/my-app haproxy.router.openshift.io/balance=roundrobin

# Rate limiting
oc annotate route/my-app haproxy.router.openshift.io/rate-limit-connections=true
oc annotate route/my-app haproxy.router.openshift.io/rate-limit-connections.rate-http=100

# Session affinity via cookie
oc annotate route/my-app router.openshift.io/cookie_name=my_session_cookie

# Connection limits per pod
oc annotate route/my-app haproxy.router.openshift.io/pod-concurrent-connections=100
```

### NodePort Service

```bash
oc edit svc <service-name>
# Set spec.type: NodePort
# Optional: set spec.ports[].nodePort (range 30000-32767)
oc get svc   # verify NodePort assignment
```

---

## ConfigMaps

### Create ConfigMaps

```bash
# From literal values
oc create configmap my-config --from-literal=key1=value1 --from-literal=key2=value2

# From file
oc create configmap my-config --from-file=config.properties

# From directory
oc create configmap my-config --from-file=./config-dir/
```

### ConfigMap YAML

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: special-config
data:
  special.how: very
  special.type: charm
  log_level: INFO
```

### Use as Environment Variables

```yaml
# Individual keys
env:
  - name: SPECIAL_LEVEL_KEY
    valueFrom:
      configMapKeyRef:
        name: special-config
        key: special.how
  - name: SPECIAL_TYPE_KEY
    valueFrom:
      configMapKeyRef:
        name: special-config
        key: special.type
        optional: true      # won't fail pod if key missing

# All keys at once
envFrom:
  - configMapRef:
      name: special-config
```

### Use as Volume Mount

```yaml
volumes:
  - name: config-volume
    configMap:
      name: special-config
containers:
  - volumeMounts:
    - name: config-volume
      mountPath: /etc/config
```

---

## Secrets

### Create Secrets

```bash
# Generic secret from literals
oc create secret generic my-secret --from-literal=username=admin --from-literal=password=s3cret

# From file
oc create secret generic my-secret --from-file=ssh-privatekey=~/.ssh/id_rsa

# TLS secret
oc create secret tls my-tls-secret --cert=tls.crt --key=tls.key

# Docker registry secret
oc create secret docker-registry my-pull-secret \
    --docker-server=registry.example.com \
    --docker-username=user --docker-password=pass
```

### Secret YAML

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: test-secret
type: Opaque
data:
  username: YWRtaW4=           # base64 encoded
  password: cDRzc3dvcmQ=       # base64 encoded
stringData:
  hostname: myapp.mydomain.com  # plain text (auto-encoded)
  secret.properties: |
    property1=valueA
    property2=valueB
```

> Use either `data` (base64-encoded) or `stringData` (plain text), not both for the same key. Individual secrets are limited to 1MB.

### Use as Environment Variables

```yaml
env:
  - name: DB_USERNAME
    valueFrom:
      secretKeyRef:
        name: test-secret
        key: username
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: test-secret
        key: password
```

### Use as Volume Mount

```yaml
volumes:
  - name: secret-volume
    secret:
      secretName: test-secret
containers:
  - volumeMounts:
    - name: secret-volume
      mountPath: /etc/secret-volume
      readOnly: true
```

### Link Secrets to Service Accounts

```bash
oc secrets link <service-account> <secret-name>
oc secrets link default my-pull-secret --for=pull    # for image pulls
oc secrets link builder my-push-secret               # for builds
```

---

## Environment Variables

```bash
# Set env vars on a deployment
oc set env deployment/my-app KEY1=value1 KEY2=value2

# Set from a secret
oc set env deployment/my-app --from=secret/my-secret

# Set from a ConfigMap
oc set env deployment/my-app --from=configmap/my-config

# List env vars
oc set env deployment/my-app --list

# Remove an env var
oc set env deployment/my-app KEY1-
```

---

## Volumes

```bash
# Add a volume from a PVC
oc set volume deployment/my-app --add --name=data-vol \
    --type=persistentVolumeClaim --claim-name=my-pvc --mount-path=/data

# Add an emptyDir volume
oc set volume deployment/my-app --add --name=tmp-vol \
    --type=emptyDir --mount-path=/tmp/data

# Add a ConfigMap volume
oc set volume deployment/my-app --add --name=config-vol \
    --type=configmap --configmap-name=my-config --mount-path=/etc/config

# Add a Secret volume
oc set volume deployment/my-app --add --name=secret-vol \
    --type=secret --secret-name=my-secret --mount-path=/etc/secret

# Remove a volume
oc set volume deployment/my-app --remove --name=data-vol

# List volumes
oc set volume deployment/my-app
```

---

## Scaling

### Manual Scaling

```bash
oc scale deployment/my-app --replicas=5
oc scale dc/frontend --replicas=3            # DeploymentConfig
```

### Autoscaling (HPA)

```bash
oc autoscale deployment/my-app --min=2 --max=10 --cpu-percent=80
```

---

## Resource Management

### Set Resource Limits and Requests

```bash
oc set resources deployment/my-app \
    --limits=cpu=500m,memory=512Mi \
    --requests=cpu=100m,memory=256Mi
```

### Resource YAML

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
      - name: my-app
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
            ephemeral-storage: "1Gi"
          limits:
            cpu: "500m"
            memory: "512Mi"
            ephemeral-storage: "2Gi"
```

> Minimum memory limit is 12 MB. When project quotas exist, you must specify resource requests.

### Resource Quotas

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
spec:
  hard:
    requests.cpu: "4"
    requests.memory: "8Gi"
    limits.cpu: "8"
    limits.memory: "16Gi"
    pods: "20"
```

```bash
oc create -f quota.yaml
oc get resourcequota
oc describe resourcequota compute-quota
```

### LimitRange (Default Limits)

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
spec:
  limits:
  - type: Container
    default:
      cpu: "500m"
      memory: "512Mi"
    defaultRequest:
      cpu: "100m"
      memory: "256Mi"
```

---

## Health Checks (Probes)

Three probe types:

| Probe | Purpose | On Failure |
|-------|---------|------------|
| **Readiness** | Can container accept traffic? | Removed from service endpoints (keeps running) |
| **Liveness** | Is container still running? | Container is killed and restarted |
| **Startup** | Has application initialized? | Other probes disabled until startup succeeds |

Three test methods:

| Method | Description | Success Criteria |
|--------|-------------|-----------------|
| **HTTP GET** | Sends HTTP request | Response code 200-399 |
| **TCP Socket** | Opens TCP connection | Connection succeeds |
| **Exec** | Runs command in container | Exit code 0 |

### Probe Configuration Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `initialDelaySeconds` | Delay before first probe | 0 |
| `periodSeconds` | Interval between probes | 10 |
| `timeoutSeconds` | Timeout per probe (must be < periodSeconds) | 1 |
| `successThreshold` | Successes needed to be considered healthy | 1 |
| `failureThreshold` | Failures before taking action | 3 |

### Example YAML

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
      - name: my-app
        image: my-app:latest
        ports:
        - containerPort: 8080
        readinessProbe:
          httpGet:
            path: /healthz
            port: 8080
            scheme: HTTPS
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 3
        livenessProbe:
          tcpSocket:
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 20
          timeoutSeconds: 5
        startupProbe:
          exec:
            command:
            - cat
            - /tmp/healthy
          failureThreshold: 30
          periodSeconds: 10
```

> Probes can only be added during pod creation. To add or modify probes on running pods, edit the Deployment/DeploymentConfig object.

---

## Deployment Triggers (DeploymentConfig)

### ConfigChange Trigger

Automatically deploys when the pod template changes:

```yaml
triggers:
  - type: "ConfigChange"
```

### ImageChange Trigger

Automatically deploys when an image stream tag updates:

```yaml
triggers:
  - type: "ImageChange"
    imageChangeParams:
      automatic: true
      from:
        kind: "ImageStreamTag"
        name: "origin-ruby-sample:latest"
        namespace: "myproject"
      containerNames:
        - "helloworld"
```

> If no triggers are defined on a DeploymentConfig, a ConfigChange trigger is added by default. To require manual deployments, set triggers to an empty array.

---

## Troubleshooting Deployments

### View Logs

```bash
oc logs deployment/my-app                    # current pod logs
oc logs deployment/my-app --previous         # previous pod logs (after crash)
oc logs deployment/my-app -c <container>     # specific container in multi-container pod
oc logs deployment/my-app -f                 # stream logs (follow)
oc logs dc/<name>                            # DeploymentConfig logs
```

### Describe Resources

```bash
oc describe deployment/my-app                # detailed deployment info + events
oc describe pod/<pod-name>                   # pod details, events, conditions
oc describe svc/my-app                       # service endpoints, selectors
oc describe route/my-app                     # route details
```

### Debug Pods

```bash
oc debug deployment/my-app                   # launch debug pod from deployment template
oc debug deployment/my-app --as-root         # debug as root user
oc debug node/<node-name>                    # debug a node
```

### Shell into Running Pods

```bash
oc rsh <pod-name>                            # start shell session
oc rsh -c <container> <pod-name>             # specific container
```

### Execute Commands in Pods

```bash
oc exec <pod-name> -- <command>              # run command
oc exec <pod-name> -c <container> -- <command>  # specific container
oc exec -it <pod-name> -- /bin/bash          # interactive terminal
```

### Port Forwarding

```bash
oc port-forward <pod-name> 8080:8080         # local:remote
oc port-forward svc/my-app 8080:8080         # forward to service
```

### View Events

```bash
oc get events --sort-by='.lastTimestamp'      # cluster events sorted by time
oc get events --field-selector involvedObject.name=<pod-name>  # events for specific pod
```

### Common Diagnostic Workflow

```bash
# 1. Check rollout status
oc rollout status deployment/my-app

# 2. Check pod status
oc get pods -l app=my-app
oc describe pod <failing-pod>

# 3. Check logs for errors
oc logs <failing-pod> --previous

# 4. Verify service endpoints
oc get endpoints my-app

# 5. Test connectivity from within cluster
oc debug deployment/my-app -- curl http://my-service:8080/healthz

# 6. Check resource usage
oc adm top pods
oc adm top nodes

# 7. Extract configmaps/secrets for inspection
oc extract configmap/my-config --to=-
oc extract secret/my-secret --to=-
```

---

## Common Resource Commands

```bash
# Get resources
oc get pods                                  # list pods
oc get all                                   # list all resources in project
oc get deployment,svc,route                  # specific resource types
oc get pods -o wide                          # wide output with node info
oc get pods -o yaml                          # full YAML output
oc get pods -o json                          # full JSON output
oc get pods -l app=my-app                    # filter by label

# Create / Apply
oc create -f resource.yaml                   # create from file
oc apply -f resource.yaml                    # create or update from file
oc apply -k ./kustomize-dir/                 # apply kustomization

# Modify
oc edit deployment/my-app                    # edit in default editor
oc patch deployment/my-app -p '{"spec":{"replicas":5}}'   # patch specific fields
oc label deployment/my-app env=production    # add label
oc annotate deployment/my-app note="v2.1"   # add annotation

# Delete
oc delete deployment/my-app                  # delete resource
oc delete -f resource.yaml                   # delete from file
oc delete pods -l app=my-app                 # delete by label

# Inspect
oc explain deployment.spec.strategy          # API schema documentation
oc diff -f resource.yaml                     # compare local vs live
oc extract secret/my-secret --to=./secrets/  # export secret to files
```

---

## Getting Help

```bash
oc help                                      # list all commands
oc <command> --help                          # help for specific command
oc explain <resource>                        # API schema for a resource
oc explain pods.spec.containers              # nested field documentation
```
