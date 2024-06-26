#! /bin/bash

# Copyright © 2020, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

cd "$(dirname $BASH_SOURCE)/../.."
source logging/bin/common.sh

this_script=`basename "$0"`

log_debug "Script [$this_script] has started [$(date)]"

# Copy template files to temp
logDir=$TMP_DIR/$LOG_NS
mkdir -p $logDir
cp -R logging/eventrouter/eventrouter.yaml $logDir/eventrouter.yaml
cp -R logging/node-placement/eventrouter-wnp.yaml $logDir/eventrouter-wnp.yaml

# Replace placeholders
log_debug "Replacing logging namespace for files in [$logDir]"
  if echo "$OSTYPE" | grep 'darwin' > /dev/null 2>&1; then
    sed -i '' "s/__LOG_NS__/$LOG_NS/g" $logDir/eventrouter*.yaml
  else
    sed -i "s/__LOG_NS__/$LOG_NS/g" $logDir/eventrouter*.yaml
  fi

# Output Kubernetes events as pseudo-log messages?
EVENTROUTER_ENABLE=${EVENTROUTER_ENABLE:-true}

if [ "$EVENTROUTER_ENABLE" != "true" ]; then
  log_info "Environment variable [EVENTROUTER_ENABLE] is not set to 'true'; exiting WITHOUT deploying Event Router"
  exit
fi

set -e

# Enable workload node placement?
LOG_NODE_PLACEMENT_ENABLE=${LOG_NODE_PLACEMENT_ENABLE:-${NODE_PLACEMENT_ENABLE:-false}}

# If performing an upgrade-in-place, check for/remove Event Router in kube-system namespace (if older than 1.1.3) 
if [[ $V4M_CURRENT_VERSION_FULL =~ 1.0 || $V4M_CURRENT_VERSION_FULL =~ 1.1.[0-2] ]]; then
   # Remove existing instance of Event Router in the kube-system namespace (if present).
   log_info "Removing instance of Event Router in the kube-system namespace"
   kubectl delete --ignore-not-found -f logging/eventrouter/eventrouter_kubesystem.yaml
fi

log_info "Deploying Event Router ..."

if [ "$LOG_NODE_PLACEMENT_ENABLE" == "true" ]; then
   log_info "Enabling eventrouter for workload node placement"
   kubectl apply -f $logDir/eventrouter-wnp.yaml
else
   log_debug "Workload node placement support is disabled for eventrouter"
   kubectl apply -f $logDir/eventrouter.yaml
fi

log_info "Event Router has been deployed"

log_debug "Script [$this_script] has completed [$(date)]"
echo ""