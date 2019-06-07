#!/bin/bash

set -exu
set -o pipefail

# GENERAL
## emoji image file directory
export EMOJI_DIR="avatars"

## include restricted users
export INCLUDE_RESTRICTED="true"

## filter by user_name, if "*" then all user. else comma separate values(ex: foo,bar,baz)
export EMOJI_TARGET="*"

## ignore users, by comma separate values(ex: foo,bar,baz)
export IGNORE_USERS="slackbot"

# split or raw. example. name: fbar => split: "f_bar", raw: "fbar"
export EMOJI_NAME_TYPE="split"

# slack user profile field name. "name" or "profile_display_name"
export SLACK_NAME_FIELD="profile.display_name"

function _get_file_name() {
  name="$1"

  if [ "$EMOJI_NAME_TYPE" = "split" ]; then
    first=$(echo "$name" | cut -c1)
    last=$(echo "$name" | cut -c2-)

    ## replace invalid chars
    echo "${first}_${last}" | tr -d "[:blank:]" | tr "." "_" | tr " " "_" | tr "[:upper:]" "[:lower:]"
  elif [ "$EMOJI_NAME_TYPE" = "raw" ]; then
    echo "$name"
  else
    echo "error: unsupported $EMOJI_NAME_TYPE."
    exit 1
  fi
}

function fetch_users() {
  curl --silent --show-error "https://slack.com/api/users.list?token=$SLACK_API_TOKEN" | jq -r '.members | map(select(.is_bot == false and .deleted == false and (.is_restricted == false or .is_restricted == '"$INCLUDE_RESTRICTED"') and .'"$SLACK_NAME_FIELD"' != "" and ((.'"$SLACK_NAME_FIELD"'|test("[^\\x01-\\x7E]"))|not) )) | map((.'"$SLACK_NAME_FIELD"'|gsub(" "; "")) + "\t" + .profile.image_72)[]'
}

function filter_users() {
  users="$1"
  target_user="$2"

  # filter not target user
  if [[ "$target_user" != "*" ]]; then
    users="$(join <(echo "$users" | sort -u) <(echo "$target_user" | tr ',' '\n' | sort -u))"
  fi

  # filter ignore users
  join -v 1 <(echo "$users" | sort -u) <(echo "$IGNORE_USERS" | tr ',' '\n' | sort -u)
}

function exit_if_not_found() {
  users="$1"
  filtered_users="$2"
  target_user="$3"

  if [[ -z $filtered_users ]]; then
    echo "$target_user was not found."
    exit 1
  fi
}

function fetch_avatar_image() {
  users="$1"

  ## reset emoji_dir
  rm -rf "$EMOJI_DIR"
  mkdir "$EMOJI_DIR"

  ## fetch avatars
  echo "$users" | while read -r name avatar
  do
    file_name=$(_get_file_name "$name")
    wget --no-verbose --output-document "$EMOJI_DIR/$file_name.jpg" "$avatar"
    sleep 0.5
  done
}

function replace_avatar() {
  users="$1"
  echo "$users" | while read -r name avatar
  do
    file_name=$(_get_file_name "$name")
    echo "removing $file_name"
    curl -X POST -w '\n' -F "name=$file_name" -F "token=$SLACK_API_TOKEN_FOR_DELETE" "https://${SLACK_TEAM}.slack.com/api/emoji.remove"
    python ./slack-emojinator/upload.py "$EMOJI_DIR/$file_name.jpg"
    sleep 0.5
  done
}

# argument
# $1 EMOJI_TARGET. will overwride $EMOJI_TARGET via `.env`
if [ "$#" -gt 0 ]; then
  target_user="$1"
else
  target_user="$EMOJI_TARGET"
fi

users=$(fetch_users)
filtered_users=$(filter_users "$users" "$target_user")
exit_if_not_found "$users" "$filtered_users" "$target_user"
fetch_avatar_image "$filtered_users"
replace_avatar "$filtered_users"
