# Loads gateway/.env without overriding variables that are already set, so
# `GITHUB_BRANCH=admin-test ./run-local.sh admin` wins over the file, and an
# explicitly empty variable stays empty. Source it with GATEWAY_DIR set.
if [ -f "$GATEWAY_DIR/.env" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|\#*) continue ;; esac
    key=${line%%=*}
    value=${line#*=}
    if [ -z "${!key+x}" ]; then export "$key=$value"; fi
  done < "$GATEWAY_DIR/.env"
fi
: "${MEMBRANE_HOME:=$HOME/Developer/Tutorials/membrane}"
: "${GITHUB_BRANCH:=main}"
: "${FEED_URL:=https://rac0r.github.io/mugensame/feed.xml}"
export MEMBRANE_HOME GITHUB_BRANCH FEED_URL
