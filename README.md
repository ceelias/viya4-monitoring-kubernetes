# Overview

This repository provides simple scripts and customization options to deploy
monitoring, alerts, and log aggregation for Viya 4.x running on Kubernetes.

Monitoring and logging may be deployed independently or together. There are
no hard dependencies between the two.

The following components are included:

## Monitoring Components

- [Prometheus Operator](https://github.com/coreos/prometheus-operator)
  - [Prometheus](https://prometheus.io/docs/introduction/overview/)
  - [Alert Manager](https://prometheus.io/docs/alerting/alertmanager/)
  - [Grafana](https://grafana.com/)
  - [node-exporter](https://github.com/prometheus/node_exporter)
  - [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics)
  - [Prometheus Adapter for Kubernetes Metrics APIs](https://github.com/DirectXMan12/k8s-prometheus-adapter)
  - [Prometheus Pushgateway](https://github.com/prometheus/pushgateway)
- Grafana dashboards
  - Kubernetes cluster monitoring (multiple dashboards)
  - SAS CAS Overview
  - SAS Java Services
  - SAS Go Services
  - RabbitMQ (multiple dashboards)
  - Postgres (multiple dashboards)
  - Fluent Bit
  - Elasticsearch
  - Istio (multiple dashboards)
  - NGINX
- Kubernetes cluster alert definitions
- [Prometheus Pushgateway](https://github.com/helm/charts/tree/master/stable/prometheus-pushgateway)

Most of the SAS components, as well as Kubernetes itself, provide built-in
support for Prometheus.

## Logging Components

- [Fluent Bit](https://fluentbit.io/)
  - Custom Fluent Bit parsers
- [Elasticsearch](https://www.elastic.co/products/elasticsearch)
  - Custom index pattern for logs
  - Namespace separation
  - [Elasticsearch Exporter](https://github.com/helm/charts/tree/master/stable/elasticsearch-exporter)
- [Kibana](https://www.elastic.co/products/kibana)
  - Custom Kibana dashboards

## Prerequisites

- You must have cluster-admin access to the Kubernetes cluster. Options for
namespace-only deployments are being investigated for future releases.

### Helm

[Helm](https://helm.sh/) Helm 2.x and 3.x are both supported. The scripts
should auto-detect the Helm version on the `PATH`.

**NOTE:** You cannot use Helm 3.x to upgrade a monitoring or logging
deployment that you originally installed with Helm 2.x. You must use
the original Helm 2.x version to remove the monitoring or logging
deployment and then use the new Helm 3.x version for a fresh deployment.

#### Recommendation: Use Helm 3.x if possible

Although both Helm 2.x and Helm 3.x are currently supported, Helm 3.x is
recommended.

If you are using Helm 2.x, run `helm init --upgrade` to make sure your
local Helm version matches the version of Tiller in your cluster. Helm 3.x
does not require Tiller or a `helm init` command.

You can safely ignore the `NOTES` sections that you see when a Helm chart
deploys successfully.

## Installation

### Monitoring

See the [monitoring README](monitoring/README.md) to deploy the monitoring
components, including Prometheus Operator, Prometheus, Alert Manager, Grafana,
service monitors, and custom dashboards.

### Logging

See the [logging README](logging/README.md) to deploy the logging components,
including Fluent Bit, ElasticSearch, and Kibana.