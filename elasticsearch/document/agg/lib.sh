# Shared functions for document aggregations

# Run an aggregation query
# Usage: agg_query <index> <field> <agg_type> <path> <query_string>
# Returns: the aggregation value, or exits with error
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

    local response
    response=$(curl -sXPOST "$ELASTICSEARCH_URL/$index/_search" -H 'Content-Type: application/json' -d "$body")

    # Check for errors
    local error
    error=$(echo "$response" | jq -r '.error.type // empty')
    if [[ -n "$error" ]]; then
        local reason
        reason=$(echo "$response" | jq -r '.error.reason // "Unknown error"')
        echo "Error: $reason" >&2
        return 1
    fi

    # Check if any documents matched
    local doc_count
    doc_count=$(echo "$response" | jq '.hits.total.value // .hits.total // 0')
    if [[ "$doc_count" == "0" ]]; then
        echo "Error: No documents found with field '$field'" >&2
        return 1
    fi

    # Get the result
    local result
    result=$(echo "$response" | jq '.aggregations.result.value')

    echo "$result"
}

# Run a value_count aggregation (for count)
# Usage: agg_count_query <index> <field> <path> <query_string>
# Returns: the count value, or exits with error
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

    local response
    response=$(curl -sXPOST "$ELASTICSEARCH_URL/$index/_search" -H 'Content-Type: application/json' -d "$body")

    # Check for errors
    local error
    error=$(echo "$response" | jq -r '.error.type // empty')
    if [[ -n "$error" ]]; then
        local reason
        reason=$(echo "$response" | jq -r '.error.reason // "Unknown error"')
        echo "Error: $reason" >&2
        return 1
    fi

    # Get the result
    local result
    result=$(echo "$response" | jq '.aggregations.result.value')

    echo "$result"
}
