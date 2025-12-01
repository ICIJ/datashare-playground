# Shared functions for document aggregations

# Run an aggregation query
# Usage: agg_query <index> <field> <agg_type> <path> <query_string>
agg_query() {
    local index=$1
    local field=$2
    local agg_type=$3
    local path=$4
    local query_string=$5

    local body='{
      "size": 0,
      "query": {
        "bool" : {
          "must" : [
            {
              "query_string": {
                "query": "'"${query_string}"'"
              }
            },
            {
              "prefix": {
                "path": "'"${path}"'"
              }
            },
            {
              "term" : {
                "type" : "Document"
              }
            },
            {
              "exists": {
                "field": "'"${field}"'"
              }
            }
          ]
        }
      },
      "aggs": {
        "result": {
          "'"${agg_type}"'": {
            "field": "'"${field}"'"
          }
        }
      }
    }'

    curl -sXPOST "$ELASTICSEARCH_URL/$index/_search" -H 'Content-Type: application/json' -d "$body" | jq '.aggregations.result.value'
}

# Run a value_count aggregation (for count)
# Usage: agg_count_query <index> <field> <path> <query_string>
agg_count_query() {
    local index=$1
    local field=$2
    local path=$3
    local query_string=$4

    local body='{
      "size": 0,
      "query": {
        "bool" : {
          "must" : [
            {
              "query_string": {
                "query": "'"${query_string}"'"
              }
            },
            {
              "prefix": {
                "path": "'"${path}"'"
              }
            },
            {
              "term" : {
                "type" : "Document"
              }
            },
            {
              "exists": {
                "field": "'"${field}"'"
              }
            }
          ]
        }
      },
      "aggs": {
        "result": {
          "value_count": {
            "field": "'"${field}"'"
          }
        }
      }
    }'

    curl -sXPOST "$ELASTICSEARCH_URL/$index/_search" -H 'Content-Type: application/json' -d "$body" | jq '.aggregations.result.value'
}
