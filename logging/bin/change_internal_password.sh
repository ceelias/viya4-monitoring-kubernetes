#! /bin/bash

# Copyright © 2020, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

cd "$(dirname "$BASH_SOURCE")/../.."
CHECK_HELM=false
source logging/bin/common.sh
source logging/bin/secrets-include.sh
source logging/bin/apiaccess-include.sh

this_script=$(basename "$0")

function show_usage {
  log_info ""
  log_info "Usage: $this_script USERNAME [PASSWORD] "
  log_info ""
  log_info "Changes the password for one of the special internal user accounts used by other components of the monitoring system to communicate "
  log_info "with OpenSearch.  In addition, the script upates the internal cache (i.e. corresponding Kubernetes secret) with the new value."
  log_info ""
  log_info "     USERNAME - REQUIRED; the internal username for which the password is be changed; "
  log_info "                MUST be one of: admin, kibanaserver, logadm, logcollector or metricgetter"
  log_info ""
  log_info "     PASSWORD - OPTIONAL; the new password.  If not provided, a random 32-character password will be generated."
  log_info "                Note: PASSWORD is REQUIRED when USERNAME is 'logadm'."
  log_info ""
  echo ""
}

if [ "$LOG_SEARCH_BACKEND" == "OPENSEARCH" ]; then
  targetpod="v4m-search-0"
  toolsrootdir="/usr/share/opensearch/plugins/opensearch-security"
else
  targetpod="v4m-es-master-0"
  toolsrootdir="/usr/share/elasticsearch/plugins/opendistro_security"
fi

USER_NAME=${1}
NEW_PASSWD="${2}"

# if no user_name; ERROR and EXIT
if [ "$USER_NAME" == "" ]; then
  log_error "Required argument [USER_NAME] not provided."
  exit 1
else
  case "$USER_NAME" in
    admin) ;;

    logcollector) ;;

    logadm)
      if [ -z "$NEW_PASSWD" ]; then
        log_error "No password provided.  A new password is REQUIRED when using this script to change the [logadm] account password"
        exit 1
      fi
      ;;
    kibanaserver) ;;

    metricgetter) ;;

    --help | -h)
      show_usage
      exit
      ;;
    *)
      log_error "The user name [$USER_NAME] you provided is not one of the supported internal users; exiting"
      show_usage
      exit 2
      ;;
  esac
fi

if [ "$NEW_PASSWD" == "" ]; then
  # generate password if one not provided
  NEW_PASSWD="$(randomPassword)"
  autogenerated_password="true"
fi

if [ "$USER_NAME" != "logadm" ]; then
  #get current credentials from Kubernetes secret
  if [ -z "$(kubectl -n "$LOG_NS" get secret internal-user-"$USER_NAME" -o=name 2>/dev/null)" ]; then
    log_warn "The Kubernetes secret [internal-user-$USER_NAME], containing credentials for the user, was not found."
    # TO DO: How to handle case where secret does not exist?  Should never happen.
    # exit
    ES_USER=$USER_NAME
  else
    ES_USER=$(kubectl -n "$LOG_NS" get secret internal-user-"$USER_NAME" -o=jsonpath="{.data.\username}" | base64 --decode)
    ES_PASSWD=$(kubectl -n "$LOG_NS" get secret internal-user-"$USER_NAME" -o=jsonpath="{.data.password}" | base64 --decode)
  fi
else
  ES_USER=$USER_NAME
  ES_PASSWD="do_not_know_current_password"
fi

get_sec_api_url

# Attempt to change password using current user credentials
response=$(curl -s -o /dev/null -w "%{http_code}" -XPUT "$sec_api_url/account" -H 'Content-Type: application/json' -d'{"current_password" : "'"$ES_PASSWD"'", "password" : "'"$NEW_PASSWD"'"}' --user "$ES_USER:$ES_PASSWD" --insecure)
if [[ $response == 4* ]]; then
  if [ "$USER_NAME" != "logadm" ]; then
    log_warn "The currently stored credentials for [$USER_NAME] do NOT appear to be up-to-date; unable to use them to change password. [$response]"
  fi

  if [ "$USER_NAME" != "admin" ]; then

    log_debug "Will attempt to use admin credentials to change password for [$USER_NAME]"

    ES_ADMIN_USER=$(kubectl -n "$LOG_NS" get secret internal-user-admin -o=jsonpath="{.data.username}" | base64 --decode)
    ES_ADMIN_PASSWD=$(kubectl -n "$LOG_NS" get secret internal-user-admin -o=jsonpath="{.data.password}" | base64 --decode)

    # make sure hash utility is executable
    kubectl -n "$LOG_NS" exec $targetpod -- chmod +x $toolsrootdir/tools/hash.sh
    # get hash of new password
    hashed_passwd=$(kubectl -n "$LOG_NS" exec $targetpod -- $toolsrootdir/tools/hash.sh -p "$NEW_PASSWD")
    rc=$?
    if [ "$rc" == "0" ]; then

      #try changing password using admin password
      response=$(curl -s -o /dev/null -w "%{http_code}" -XPATCH "$sec_api_url/internalusers/$ES_USER" -H 'Content-Type: application/json' -d'[{"op" : "replace", "path" : "hash", "value" : "'"$hashed_passwd"'"}]' --user "$ES_ADMIN_USER":"$ES_ADMIN_PASSWD" --insecure)
      if [[ "$response" == "404" ]]; then
        log_error "Unable to change password for [$USER_NAME] because that user does not exist. [$response]"
        success="non-existent_user"
      elif [[ $response == 4* ]]; then
        log_error "The Kubernetes secret containing credentials for the [admin] user appears to be out-of-date. [$response]"
        echo ""
        log_error "                                *********** IMPORTANT NOTE ***********"
        log_error ""
        log_error " Cached credentials for [admin] user are not valid!"
        log_error ""
        log_error " It is VERY IMPORTANT to ensure the credentials for the [admin] account and the corresponding"
        log_error " Kubernetes secret [internal-user-admin] in the [$LOG_NS] namespace are ALWAYS synchronized."
        log_error ""
        log_error " You MUST re-run this script NOW with the updated password for the [admin] account to update"
        log_error " the secret with the current password."
        log_error ""
        log_error " You may then run this script again to update the password for the [$USER_NAME] account."
        echo ""
        success="false"
      elif [[ $response == 2* ]]; then
        log_debug "Password for [$USER_NAME] has been changed in OpenSearch. [$response]"
        success="true"
      else
        log_warn "Unable to change password for [$USER_NAME] using [admin] credentials. [$response]"
        success="false"
      fi
    else
      log_error "Unable to obtain a hash of the new password; password not changed. [rc: $rc]"
    fi
  else
    log_debug "Attempting to change password for user [admin] using the admin certs rather than cached password"

    # make sure hash utility is executable
    kubectl -n "$LOG_NS" exec $targetpod -- chmod +x $toolsrootdir/tools/hash.sh
    # get hash of new password
    hashed_passwd=$(kubectl -n "$LOG_NS" exec $targetpod -- $toolsrootdir/tools/hash.sh -p "$NEW_PASSWD")

    #obtain admin cert
    rm -f "$TMP_DIR"/tls.crt
    admin_tls_cert=$(kubectl -n "$LOG_NS" get secrets es-admin-tls-secret -o "jsonpath={.data['tls\.crt']}")
    if [ -z "$admin_tls_cert" ]; then
      log_error "Unable to obtain admin certs from secret [es-admin-tls-secret] in the [$LOG_NS] namespace. Password for [$USER_NAME] has NOT been changed."
      success="false"
    else
      log_debug "File tls.crt obtained from Kubernetes secret"
      echo "$admin_tls_cert" | base64 --decode >"$TMP_DIR"/admin_tls.crt

      #obtain admin TLS key
      rm -f "$TMP_DIR"/tls.key
      admin_tls_key=$(kubectl -n "$LOG_NS" get secrets es-admin-tls-secret -o "jsonpath={.data['tls\.key']}")
      if [ -z "$admin_tls_key" ]; then
        log_error "Unable to obtain admin cert key from secret [es-admin-tls-secret] in the [$LOG_NS] namespace. Password for [$USER_NAME] has NOT been changed."
        success="false"
      else
        log_debug "File tls.key obtained from Kubernetes secret"
        echo "$admin_tls_key" | base64 --decode >"$TMP_DIR"/admin_tls.key

        # Attempt to change password using admin certs
        response=$(curl -s -o /dev/null -w "%{http_code}" -XPATCH "$sec_api_url/internalusers/$ES_USER" -H 'Content-Type: application/json' -d'[{"op" : "replace", "path" : "hash", "value" : "'"$hashed_passwd"'"}]' --cert "$TMP_DIR"/admin_tls.crt --key "$TMP_DIR"/admin_tls.key --insecure)
        if [[ $response == 2* ]]; then
          log_debug "Password for [$USER_NAME] has been changed in OpenSearch. [$response]"
          success="true"
        else
          log_warn "Unable to change password for [$USER_NAME] using [admin] certificates. [$response]"
          success="false"
        fi
      fi
    fi
  fi
elif [[ $response == 2* ]]; then
  log_debug "Password change response [$response]"
  success="true"
else
  log_error "An unexpected problem was encountered while attempting to update password for [$USER_NAME]; password not changed [$response]"
  success="false"
fi

if [ "$success" == "true" ]; then
  log_info "Successfully changed the password for [$USER_NAME] in OpenSearch internal database."

  if [ "$USER_NAME" != "logadm" ]; then
    log_debug "Trying to store the updated credentials in the corresponding Kubernetes secret [internal-user-$USER_NAME]."

    kubectl -n "$LOG_NS" delete secret internal-user-"$USER_NAME" --ignore-not-found

    labels="managed-by=v4m-es-script"
    if [ "$autogenerated_password" == "true" ]; then
      labels="$labels autogenerated_password=true"
    fi

    create_user_secret internal-user-"$USER_NAME" "$USER_NAME" "$NEW_PASSWD" "$labels"
    rc=$?
    if [ "$rc" != "0" ]; then
      log_error "IMPORTANT! A Kubernetes secret holding the password for $USER_NAME no longer exists."
      log_error "This WILL cause problems when the OpenSearch pods restart."
      log_error "Try re-running this script again OR manually creating the secret using the command: "
      log_error "kubectl -n $LOG_NS create secret generic --from-literal=username=$USER_NAME --from-literal=password=$NEW_PASSWD"
    else
      case $USER_NAME in
        admin)

          if [ "$autogenerated_password" == "true" ]; then
            echo ""
            log_notice "                    *********** IMPORTANT NOTE ***********                  "
            log_notice ""
            log_notice " The password for the OpenSearch 'admin' user was changed as requested.  "
            log_notice "                                                                            "
            log_notice " Since a new password for the 'admin' user was NOT provided, one was        "
            log_notice " auto-generated for the account. The generated password is shown below.     "
            log_notice "                                                                            "
            log_notice " Generated 'admin' password:  $NEW_PASSWD                                       |"
            log_notice "                                                                            "
            log_notice " You can change the password for the 'admin' account at any time, by        "
            log_notice " re-running this script.                                                    "
            log_notice "                                                                            "
            log_notice " NOTE: *NEVER* change the password for the 'admin' account from within the  "
            log_notice " OpenSearch Dashboards web-interface.  The 'admin' password should *ONLY* be changed via   "
            log_notice " this script (logging/bin/change_internal_password.sh)                      "
            echo ""
          fi
          ;;
        logcollector)
          echo ""
          log_notice "                    *********** IMPORTANT NOTE ***********                   "
          log_notice "                                                                             "
          log_notice " After changing the password for the [logcollector] user, you should restart "
          log_notice " the Fluent Bit pods to ensure log collection is not interrupted.            "
          log_notice "                                                                             "
          log_notice " This can be done by submitting the following command:                       "
          log_notice "         kubectl -n $LOG_NS delete pods -l 'app=fluent-bit, fbout=es'        "
          echo ""
          ;;
        kibanaserver)
          echo ""
          log_notice "                        *********** IMPORTANT NOTE ***********                        "
          log_notice "                                                                                      "
          log_notice " After changing the password for the [kibanaserver] user, you need to restart the     "
          if [ "$LOG_SEARCH_BACKEND" == "OPENSEARCH" ]; then
            log_notice " OpenSearch Dashboards pod to ensure OpenSearch Dashboards can still be accessed and used. "
            log_notice "                                                                                      "
            log_notice " This can be done by submitting the following command:                                "
            log_notice "              kubectl -n $LOG_NS delete pods -l 'app=opensearch-dashboards'"
          else
            log_notice " Kibana pod to ensure Kibana can still be accessed and used."
            log_notice ""
            log_notice " This can be done by submitting the following command:"
            log_notice "       kubectl -n $LOG_NS delete pods -l 'app=v4m-es,role=kibana'"
          fi
          echo ""
          ;;
        metricgetter)
          echo ""
          log_notice "                        *********** IMPORTANT NOTE ***********                        "
          log_notice "                                                                                      "
          log_notice " After changing the password for the [metricgetter] user, you should restart the      "
          log_notice " Elasticsearch Exporter pod to ensure OpenSearch metrics continue to be collected. "
          log_notice "                                                                                      "
          log_notice " This can be done by submitting the following command:                                "
          log_notice "           kubectl -n $LOG_NS delete pod -l 'app=elasticsearch-exporter' "
          echo ""
          ;;
        *)
          log_error "The user name [$USER_NAME] you provided is not one of the supported internal users; exiting"
          exit 2
          ;;
      esac
    fi
  fi
elif [ "$success" == "false" ]; then
  log_error "Unable to update the password for user [$USER_NAME] on the OpenSearch pod; original password remains in place."
  exit 99
fi
