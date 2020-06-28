# Copyright © 2020, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# This file is not marked as executable as it is intended to be sourced
# Current directory must be the root directory of the repo

if [ "$SAS_LOGGING_COMMON_SOURCED" = "" ]; then
    source bin/common.sh
    

    if [ -f "logging/user.env" ]; then
        userEnv=$(grep -v '^[[:blank:]]*$' logging/user.env | grep -v '^#' | xargs)
        log_info "Loading user environment file: logging/user.env"
        if [ "$userEnv" != "" ]; then
          export $userEnv
        fi
    fi
    
    export LOG_NS="${LOG_NS:-logging}"
    export SAS_LOGGING_COMMON_SOURCED=true
fi
echo ""