#!/bin/bash -e

# This quick and dirty script will remove deleted documents from all indices in an Elasticsearch cluster.
# It will set the expunge_deletes_allowed setting to 0%, trigger a forcemerge
# to remove the deleted documents, and then set the setting back to the a new default 5%.


script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 1 '<index>'
check_env
check_bins
check_elasticsearch_url

default_setting="5" # Target default value (5%)
index=$1
esindex=$ELASTICSEARCH_URL/$index

# Close the index to modify static settings
curl -s -XPOST "$esindex/_close" > /dev/null

# Update expunge_deletes_allowed to 1%
curl -s -XPUT "$esindex/_settings" -H 'Content-Type: application/json' -d'
{
  "index.merge.policy.expunge_deletes_allowed": "0"
}' > /dev/null

# Reopen the index
curl -s -XPOST "$esindex/_open" > /dev/null

# Trigger forcemerge (async)
echo "Forcemerge triggered for $index"
curl -s -XPOST "$esindex/_forcemerge?only_expunge_deletes=true" > /dev/null &

echo "Waiting until all forcemerge tasks are done"
while curl -s $ELASTICSEARCH_URL/_cat/tasks\?v  | grep forcemerge > /dev/null ; do
  curl -s $ELASTICSEARCH_URL/_cat/indices | grep $index
  sleep 10
done

# Close the index again
curl -s -XPOST "$esindex/_close" > /dev/null

# Update to the new default (5%)
curl -s -XPUT "$esindex/_settings" -H 'Content-Type: application/json' -d'
{
  "index.merge.policy.expunge_deletes_allowed": "'"$default_setting"'"
}' > /dev/null

# Reopen the index
curl -s -XPOST "$esindex/_open" > /dev/null

echo "Done! The $index index was updated."
