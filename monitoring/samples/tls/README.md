# Sample - TLS Enablement for Monitoring

## Overview

This sample demonstrates how to deploy monitoring components with TLS enabled.

All components have TLS enabled on ingress. Due to limitations in the
underlying Helm charts, some components might not have TLS enabled in-cluster.
See the Limitations and Known Issues section below for details.

If you use this sample for HTTPS for ingress, the following secrets must be manually populated in the `monitoring` namespace (or `MON_NS` value) **BEFORE** you run any of the scripts in this repository:

* kubernetes.io/tls secret - `prometheus-ingress-tls-secret`
* kubernetes.io/tls secret - `alertmanager-ingress-tls-secret`
* kubernetes.io/tls secret - `grafana-ingress-tls-secret`

Generating these certificates is outside the scope of this example.However, you can use the
process documented in "Configure NGINX Ingress TLS for SAS Applications" in SAS Viya Administation documentation and specify the `monitoring` namespace.

For in-cluster (east-west traffic) TLS for monitoring components,  
[cert-manager](https://cert-manager.io/) populates the following
secrets that contain pod certificates (existing secrets are not overwritten,
so they can still be manually populated):

* kubernetes.io/tls secret - `prometheus-tls-secret`
* kubernetes.io/tls secret - `alertmanager-tls-secret`
* kubernetes.io/tls secret - `grafana-tls-secret`

## Instructions

1. Set up an empty directory with a `monitoring` subdirectory to contain the customization files. 

2. Export a `USER_DIR` environment variable pointing to this
location. For example:

```bash
mkdir -p ~/my-cluster-files/ops/user-dir/monitoring
export USER_DIR=~/my-cluster-files/ops/user-dir
```

3. Create `$USER_DIR/monitoring/user.env`. Specify this value in the file:

* `MON_TLS_ENABLE=true` - This flag modifies the deployment of Prometheus,
Grafana, and AlertManager to be TLS-enabled.

4. Copy the sample TLS helm user response file to your `USER_DIR`:

```bash
cp path/to/this/repo/monitoring/samples/tls/user-values-prom-operator.yaml $USER_DIR/monitoring/
```

5. Edit `$USER_DIR/monitoring/user-values-prom-operator.yaml` and replace
any sample hostnames with hostnames for your deployment. Specifically, you must replace
`host.cluster.example.com` with the name of the ingress node. Often, the ingress node is the cluster master node, but environments vary.

6. Specify any other customizations to the YAML.

7. After you have followed these steps to set up `USER_DIR`, deploy cluster
monitoring normally:

```bash
path/to/this/repo/monitoring/bin/deploy_monitoring_cluster.sh
```

## Limitations and Known Issues

* There is a [bug in the AlertManager Helm template](https://github.com/helm/charts/issues/22939)
that prevents mounting the TLS certificates for the reverse proxy sidecar.
It is expected that this issue will be addressed before GA. HTTPS is still
supported for AlertManager at the ingress level, but it is not supported for the pod (in-cluster).

* The Prometheus node exporter and kube-state-metrics exporters do not currently
support TLS. These components are not exposed over ingress, so in-cluster
access will be over HTTP and not HTTPS.

* If needed, a self-signed cert-manager Issuer is created that generates
self-signed certificates when TLS is enabled and the secrets do no already
exist. By default, in-cluster traffic between monitoring components (not ingress) is
configured to skip TLS CA verification.