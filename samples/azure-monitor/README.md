# Azure Monitor Integration

## Scrape Prometheus Metrics Endpoints

SAS Viya components are natively instrumented to expose a Prometheus-compatible
HTTP or HTTPS metrics endpoint. This sample shows how to configure Azure
Monitor to automatically discover and scrape these endpoints.

See the [Azure documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/insights/container-insights-prometheus-integration)
to understand how Azure Monitor discovers and scrapes endpoints.

Follow these steps to enable Azure Monitor for your cluster.

1. Download the
[template](https://github.com/microsoft/Docker-Provider/blob/ci_dev/kubernetes/container-azm-ms-agentconfig.yaml)
ConfigMap yaml.

2. Customize the `prometheus-data-collection-settings` section. Use the yaml
file provided in this sample [here](container-azm-ms-agentconfig.yaml) as a
guide. Recommended changes include:

- `interval` - Update from `1m` to `30s` (recommended, but not required)
- `monitor_kubernetes_pods` - Set to `true`.
- `monitor_kubernetes_pods` - Set to `true` to enable Azure Monitor to
auto-discover pods to monitor, based on the standard Prometheus annotations.
SAS Viya components that expose metrics endpoints should include these
annotations:

- `promethues.io/scrape` - `true` or `false`
- `promethues.io/path` - path to metrics endpoint
- `promethues.io/port`- metrics port
- `promethues.io/scheme`- `http` or `https`

3. After customizing the template, apply it to the cluster by using this command:

```bash
kubectl apply -f /path/to/container-azm-ms-agentconfig.yaml
```

**Note:** It might take 3-5 minutes for the monitoring agents to restart and for 
data collection to begin.

## Example Queries - Metrics

The following are some sample queries that demonstrate how you can visualize the newly
collected Prometheus metric data.

### go_threads for sas-folders

```text
InsightsMetrics
| where Namespace == "prometheus"
| where Name == "go_threads"
| where parse_json(Tags).app == "sas-folders"
```

### Show Resident Memory for a Service in MB

```text
InsightsMetrics
| extend T=parse_json(Tags)
| extend App=tostring(T.app)
| where Namespace == "prometheus"
| where Name == "process_resident_memory_bytes"
| project TimeGenerated, Name, App, ResidentMemoryMB=Val/1024/1024
| render timechart
```

### Show a Metric across Multiple Services

```text
InsightsMetrics
| where Namespace == "prometheus"
| where Name == "go_threads"
| project TimeGenerated, tostring(App = parse_json(Tags).app), Val
| render timechart
```

### Show sas_* Metrics for a Service

```text
InsightsMetrics
| where Namespace == "prometheus"
| where Name matches regex "sas_"
| where parse_json(Tags).app == "sas-folders"
| extend App = tostring(App = parse_json(Tags).app)
| project TimeGenerated, Name, App, Val
| render timechart
```

### Show Used Memory for a SAS Go Service

```text
InsightsMetrics
| extend App = tostring(App = parse_json(Tags).app)
| where Namespace == "prometheus"
| where Name == "go_memstats_alloc_bytes"
| where App == "sas-folders"
| extend Pod = tostring(parse_json(Tags).pod_name)
| project TimeGenerated, Name, App, Tags, Pod, MemUsageMB=Val/1024.0/1024.0
| render timechart
```

### Calculate Rate

```text
InsightsMetrics
| extend App = tostring(App = parse_json(Tags).app)
| where Namespace == "prometheus"
| where Name == "process_cpu_seconds_total"
| where App == "sas-folders"
| sort by TimeGenerated desc
| extend nextVal = next(Val,1,-1)
| extend diff=iif(nextVal==-1,0.0,Val - nextVal)
| project TimeGenerated, Name, App, CPUCores=diff
| render timechart
```

## Example Queries - Logs

```text
ContainerLog
//KubePodInventory Contains namespace information
| join(KubePodInventory| where TimeGenerated > startofday(ago(6h))) on ContainerID
| extend L=parse_json(LogEntry)
| where L.source matches regex "sas-.+"
| where L.level == "warn" or L.level == "error" or L.level == "fatal"
| where TimeGenerated > startofday(ago(3h))
| project TimeGenerated ,Namespace, L.level, L.source, L.message
```

## Example Queries - Events

```text
KubeEvents
| where TimeGenerated > ago(7d)
| where not(isempty(Namespace))
| where KubeEventType == "Warning"
| project TimeGenerated, Namespace, ObjectKind, Name, Reason, Message, FirstSeen, LastSeen, Count, Computer, ClusterName
| top 200 by TimeGenerated desc
```

## Additional Information

- [Azure Prometheus Integration](https://docs.microsoft.com/en-us/azure/azure-monitor/insights/container-insights-prometheus-integration)
- [Querying Azure Metrics](https://docs.microsoft.com/en-us/azure/azure-monitor/insights/container-insights-log-search#search-logs-to-analyze-data)
