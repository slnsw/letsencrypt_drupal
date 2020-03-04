#!/usr/bin/env bash

# Environment variables that need to be available:
# * PROJECT
# * ENVIRONMENT

# Build up all required variables.
DRUSH_ALIAS="@${PROJECT}.${ENVIRONMENT}"
DRUSH_ALIAS_NO_AT="${PROJECT}.${ENVIRONMENT}"
# Project root is a known path on Acquia Cloud.
PROJECT_ROOT="/var/www/html/${PROJECT}.${ENVIRONMENT}"
FILE_CONFIG=${PROJECT_ROOT}/letsencrypt_drupal/config_${PROJECT}.${ENVIRONMENT}.sh
DIRECTORY_DEHYDRATED_CONFIG=${PROJECT_ROOT}/letsencrypt_drupal/dehydrated
FILE_DOMAINSTXT=${PROJECT_ROOT}/letsencrypt_drupal/domains_${PROJECT}.${ENVIRONMENT}.txt
DEHYDRATED="https://github.com/dehydrated-io/dehydrated.git"
CERT_DIR=~/.letsencrypt_drupal
TMP_DIR=/tmp/letsencrypt_drupal_${PROJECT}
FILE_BASECONFIG=${TMP_DIR}/baseconfig
FILE_DRUSH_ALIAS=${TMP_DIR}/drush_alias
FILE_DRUPAL_VERSION=${TMP_DIR}/drupal_version
FILE_PROJECT_ROOT=${TMP_DIR}/project_root
LOCK_FILENAME=/tmp/cert_renew_lock_${PROJECT}

# Detect core version
DRUPAL_VERSION="9"
if grep -q -r -i --include Drupal.php "const version" ${PROJECT_ROOT}; then DRUPAL_VERSION="8"; fi
if grep -q -r -i --include bootstrap.inc "define('VERSION', '" ${PROJECT_ROOT}; then DRUPAL_VERSION="7"; fi

# Load all variables provided by the project.
. ${FILE_CONFIG}

#---------------------------------------------------------------------
acquire_lock_or_exit()
{
  # Check we are not running already: http://mywiki.wooledge.org/BashFAQ/045
  exec 8>${LOCK_FILENAME}
  if ! flock -n 8  ; then
    logline "Another instance of this script running.";
    exit 1
  fi
  # This now runs under the lock until 8 is closed (it will be closed automatically when the script ends)
}

#---------------------------------------------------------------------
slackpost()
{
  # Can either be one of 'good', 'warning', 'danger', or any hex color code
  COLOR="${2}"
  USERNAME="${3}"
  TEXT="${4}"

  if [[ "$SLACK_WEBHOOK_URL" =~ ^https:\/\/hooks.slack.com* ]]; then
    # based on https://gist.github.com/dopiaza/6449505
#    echo "BEFORE"
#    echo "$TEXT"
    escapedText=$(echo $TEXT | sed 's/"/\"/g' | sed "s/'/\'/g")
#    echo "AFTER"
#    echo "$escapedText"
    json="{\"channel\": \"$SLACK_CHANNEL\", \"username\":\"$USERNAME\", \"icon_emoji\":\"ghost\", \"attachments\":[{\"color\":\"$COLOR\" , \"text\": \"$escapedText\"}]}"
    curl -s -d "payload=$json" "$SLACK_WEBHOOK_URL" || logline "Failed to send message to slack: ${USERNAME}: ${TEXT}"
  else
    logline "No Slack: ${USERNAME}: ${TEXT}"
  fi
}

#---------------------------------------------------------------------
logline()
{
  printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

#---------------------------------------------------------------------
cd_or_exit()
{
  rv=0
  cd "$1" || rv=$?
  if [ $rv -ne 0 ]; then
    logline "Failed to cd into $1 directory. exiting."
    exit 31
  fi
}

#---------------------------------------------------------------------
drush_set_challenge()
{
  DRUSH_ALIAS="${1}"
  DRUPAL_VERSION="${2}"
  DOMAIN="${3}"
  TOKEN_VALUE="${4}"

  if [[ "${DRUPAL_VERSION}" == "7" ]]; then
    drush ${DRUSH_ALIAS} en -y --uri=${DOMAIN} letsencrypt_challenge
    drush ${DRUSH_ALIAS} vset -y --uri=${DOMAIN} letsencrypt_challenge "${TOKEN_VALUE}"
  elif [[ "${DRUPAL_VERSION}" == "8" ]]; then
    drush ${DRUSH_ALIAS} en -y --uri=${DOMAIN} letsencrypt_challenge
    drush ${DRUSH_ALIAS} sset -y --uri=${DOMAIN} letsencrypt_challenge.challenge "${TOKEN_VALUE}"
  elif [[ "${DRUPAL_VERSION}" == "9" ]]; then
    drush ${DRUSH_ALIAS} en -y --uri=${DOMAIN} letsencrypt_challenge
    drush ${DRUSH_ALIAS} sset -y --uri=${DOMAIN} letsencrypt_challenge.challenge "${TOKEN_VALUE}"
  fi
}

#---------------------------------------------------------------------
drush_add_challenge()
{
  DRUSH_ALIAS="${1}"
  DRUPAL_VERSION="${2}"
  DOMAIN="${3}"
  TOKEN_VALUE="${4}"

  # @TODO Get proper drush task for Drupal 8 and 9.

  if [[ "${DRUPAL_VERSION}" == "7" ]]; then
    drush ${DRUSH_ALIAS} en -y --uri=${DOMAIN} letsencrypt_challenge
    drush ${DRUSH_ALIAS} letsencrypt-challenge-add -y --uri=${DOMAIN} "${TOKEN_VALUE}"
  elif [[ "${DRUPAL_VERSION}" == "8" ]]; then
    drush ${DRUSH_ALIAS} en -y --uri=${DOMAIN} letsencrypt_challenge
    drush ${DRUSH_ALIAS} sset -y --uri=${DOMAIN} letsencrypt_challenge.challenge "${TOKEN_VALUE}"
  elif [[ "${DRUPAL_VERSION}" == "9" ]]; then
    drush ${DRUSH_ALIAS} en -y --uri=${DOMAIN} letsencrypt_challenge
    drush ${DRUSH_ALIAS} sset -y --uri=${DOMAIN} letsencrypt_challenge.challenge "${TOKEN_VALUE}"
  fi
}

#---------------------------------------------------------------------
drush_clear_challenge()
{
  DRUSH_ALIAS="${1}"
  DRUPAL_VERSION="${2}"
  DOMAIN="${3}"
  TOKEN_VALUE="${4}"

  # @TODO Get proper drush task for Drupal 8 and 9.

  if [[ "${DRUPAL_VERSION}" == "7" ]]; then
    drush ${DRUSH_ALIAS} en -y --uri=${DOMAIN} letsencrypt_challenge
    drush ${DRUSH_ALIAS} letsencrypt-challenge-clear -y --uri=${DOMAIN}
  elif [[ "${DRUPAL_VERSION}" == "8" ]]; then
    drush ${DRUSH_ALIAS} en -y --uri=${DOMAIN} letsencrypt_challenge
    drush ${DRUSH_ALIAS} sset -y --uri=${DOMAIN} letsencrypt_challenge.challenge ""
  elif [[ "${DRUPAL_VERSION}" == "9" ]]; then
    drush ${DRUSH_ALIAS} en -y --uri=${DOMAIN} letsencrypt_challenge
    drush ${DRUSH_ALIAS} sset -y --uri=${DOMAIN} letsencrypt_challenge.challenge ""
  fi
}
