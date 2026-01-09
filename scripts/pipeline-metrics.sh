#!/bin/sh
set -e

# Function to output to both console and file
report() {
  echo "$@" | tee -a metrics.txt
}

report "=========================================="
report "Pipeline Metrics Report"
report "=========================================="
report ""

# Pipeline info
report "Pipeline Information:"
report "  Pipeline ID: $CI_PIPELINE_ID"
report "  Pipeline URL: $CI_PIPELINE_URL"
report "  Started at: $CI_PIPELINE_CREATED_AT"
report "  Branch: $CI_COMMIT_REF_NAME"
report "  Commit: $CI_COMMIT_SHORT_SHA"
report ""

# Check if METRICS_TOKEN is set
if [ -z "$METRICS_TOKEN" ]; then
  report "Note: Set METRICS_TOKEN variable for detailed metrics"
  report "(Create at: Settings > Access Tokens with 'read_api' scope)"
  report ""
else
  # Debug: Log API endpoint (without exposing token)
  echo "DEBUG: Fetching from API /projects/$CI_PROJECT_ID/pipelines/$CI_PIPELINE_ID" >&2

  # Get pipeline details via API with better error handling
  PIPELINE_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" --header "PRIVATE-TOKEN: $METRICS_TOKEN" \
    "https://gitlab.com/api/v4/projects/$CI_PROJECT_ID/pipelines/$CI_PIPELINE_ID")

  HTTP_STATUS=$(echo "$PIPELINE_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
  PIPELINE_DATA=$(echo "$PIPELINE_RESPONSE" | sed '/HTTP_STATUS:/d')

  echo "DEBUG: Pipeline API returned status: $HTTP_STATUS" >&2

  # Check if API call was successful
  if [ "$HTTP_STATUS" = "200" ] && [ -n "$PIPELINE_DATA" ] && echo "$PIPELINE_DATA" | jq empty >/dev/null 2>&1; then
    DURATION=$(echo "$PIPELINE_DATA" | jq -r '.duration // null' 2>/dev/null)
    PIPELINE_STATUS=$(echo "$PIPELINE_DATA" | jq -r '.status // "unknown"' 2>/dev/null)
    CREATED_AT=$(echo "$PIPELINE_DATA" | jq -r '.created_at // "N/A"' 2>/dev/null)
    UPDATED_AT=$(echo "$PIPELINE_DATA" | jq -r '.updated_at // "N/A"' 2>/dev/null)

    report "Pipeline Duration:"
    report "  Status: $PIPELINE_STATUS"
    if [ "$DURATION" != "null" ] && [ -n "$DURATION" ] && [ "$DURATION" != "0" ]; then
      report "  Total time: ${DURATION} seconds ($(awk "BEGIN {printf \"%.2f\", $DURATION/60}") minutes)"
    elif [ "$PIPELINE_STATUS" = "running" ]; then
      # Calculate elapsed time since pipeline started
      if command -v date >/dev/null 2>&1; then
        START_TIME=$(date -u -d "$CREATED_AT" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "$(echo $CREATED_AT | cut -d. -f1)" +%s 2>/dev/null || echo "0")
        CURRENT_TIME=$(date -u +%s)
        if [ "$START_TIME" != "0" ]; then
          ELAPSED=$((CURRENT_TIME - START_TIME))
          report "  Elapsed time: ${ELAPSED} seconds ($(awk "BEGIN {printf \"%.2f\", $ELAPSED/60}") minutes) - Pipeline still running"
        else
          report "  Pipeline is still running"
        fi
      else
        report "  Pipeline is still running"
      fi
    else
      report "  Duration not available yet"
    fi
    report ""

    # Get job details
    report "Job Performance:"
    JOBS_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" --header "PRIVATE-TOKEN: $METRICS_TOKEN" \
      "https://gitlab.com/api/v4/projects/$CI_PROJECT_ID/pipelines/$CI_PIPELINE_ID/jobs")

    JOBS_HTTP_STATUS=$(echo "$JOBS_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
    JOBS=$(echo "$JOBS_RESPONSE" | sed '/HTTP_STATUS:/d')

    echo "DEBUG: Jobs API returned status: $JOBS_HTTP_STATUS" >&2
    echo "DEBUG: Jobs data length: ${#JOBS}" >&2

    if [ "$JOBS_HTTP_STATUS" = "200" ]; then
      # Validate JSON
      if echo "$JOBS" | jq empty >/dev/null 2>&1; then
        JOB_COUNT=$(echo "$JOBS" | jq 'length' 2>/dev/null)
        echo "DEBUG: Found $JOB_COUNT jobs" >&2

        if [ "$JOB_COUNT" -gt 0 ]; then
          # Display all jobs with their status
          report "  Jobs executed:"
          echo "$JOBS" | jq -r '.[] |
            "  - \(.name): \(if .duration then "\(.duration)s" else "N/A" end) (\(.status))"' 2>/dev/null | tee -a metrics.txt

          report ""

          # Show completed jobs sorted by duration
          COMPLETED_JOBS=$(echo "$JOBS" | jq '[.[] | select(.status == "success" or .status == "failed")]' 2>/dev/null)
          COMPLETED_COUNT=$(echo "$COMPLETED_JOBS" | jq 'length' 2>/dev/null)

          if [ "$COMPLETED_COUNT" -gt 0 ]; then
            report "  Completed jobs (sorted by duration):"
            echo "$COMPLETED_JOBS" | jq -r '.[] |
              "\(.duration // 0)\t\(.name)\t\(.status)"' 2>/dev/null | \
              sort -nr | \
              awk '{printf "  - %s: %ss (%s)\n", $2, $1, $3}' | tee -a metrics.txt
            report ""
          fi

          report "Authentication Method: Workload Identity Federation (Keyless)"
          report "Cloud Provider: Google Cloud Platform"
          report "CI/CD Platform: GitLab CI"
          report ""

          # Calculate statistics
          TOTAL_JOB_TIME=$(echo "$JOBS" | jq '[.[] | select(.duration != null) | .duration] | add // 0' 2>/dev/null)
          SUCCESSFUL_JOBS=$(echo "$JOBS" | jq '[.[] | select(.status == "success")] | length' 2>/dev/null)
          FAILED_JOBS=$(echo "$JOBS" | jq '[.[] | select(.status == "failed")] | length' 2>/dev/null)
          RUNNING_JOBS=$(echo "$JOBS" | jq '[.[] | select(.status == "running")] | length' 2>/dev/null)

          report "Job Statistics:"
          report "  Total jobs: $JOB_COUNT"
          report "  Successful: $SUCCESSFUL_JOBS"
          report "  Failed: $FAILED_JOBS"
          report "  Running: $RUNNING_JOBS"

          if [ -n "$TOTAL_JOB_TIME" ] && [ "$TOTAL_JOB_TIME" != "0" ]; then
            report "  Total execution time: ${TOTAL_JOB_TIME} seconds ($(awk "BEGIN {printf \"%.2f\", $TOTAL_JOB_TIME/60}") minutes)"

            if [ "$DURATION" != "null" ] && [ -n "$DURATION" ] && [ "$DURATION" != "0" ]; then
              EFFICIENCY=$(awk "BEGIN {printf \"%.1f\", ($TOTAL_JOB_TIME/$DURATION)*100}")
              report "  Pipeline efficiency: ${EFFICIENCY}%"

              # Calculate parallelization benefit
              SERIAL_TIME=$TOTAL_JOB_TIME
              PARALLEL_SAVED=$((SERIAL_TIME - DURATION))
              if [ $PARALLEL_SAVED -gt 0 ]; then
                report "  Time saved by parallelization: ${PARALLEL_SAVED} seconds ($(awk "BEGIN {printf \"%.2f\", $PARALLEL_SAVED/60}") minutes)"
              fi
            fi
          fi
          report ""
        else
          report "  No jobs found in pipeline"
          report ""
        fi
      else
        report "  Error: Invalid JSON response from jobs API"
        echo "DEBUG: Jobs response: $JOBS" >&2
        report ""
      fi
    else
      if [ "$JOBS_HTTP_STATUS" = "401" ]; then
        report "  Error: Authentication failed (HTTP 401)"
        report "  - Verify METRICS_TOKEN has 'read_api' scope"
        report "  - Check token hasn't expired"
      elif [ "$JOBS_HTTP_STATUS" = "403" ]; then
        report "  Error: Access forbidden (HTTP 403)"
        report "  - Token may not have permission to access this project"
      elif [ "$JOBS_HTTP_STATUS" = "404" ]; then
        report "  Error: Pipeline not found (HTTP 404)"
      else
        report "  Error: API request failed (HTTP status: $JOBS_HTTP_STATUS)"
      fi
      echo "DEBUG: Jobs response: $JOBS" >&2
      report ""
    fi
  else
    report "Pipeline Duration:"
    report "  Total time: N/A seconds ( minutes)"
    report ""

    report "Job Performance:"
    report "  Unable to fetch pipeline details (HTTP status: $HTTP_STATUS)"

    if [ "$HTTP_STATUS" = "401" ]; then
      report "  - Token authentication failed"
      report "  - Verify METRICS_TOKEN has 'read_api' scope"
    elif [ "$HTTP_STATUS" = "403" ]; then
      report "  - Access forbidden - check token permissions"
    elif [ "$HTTP_STATUS" = "404" ]; then
      report "  - Pipeline not found - verify project ID and pipeline ID"
    elif [ -z "$HTTP_STATUS" ]; then
      report "  - No response from API - check network connectivity"
    fi

    echo "DEBUG: Pipeline response: $PIPELINE_DATA" >&2
    report ""
  fi
fi

report "Deployment Components:"
report "  - Cloud Run (Container Runtime)"
report "  - Cloud SQL PostgreSQL (Database)"
report "  - API Gateway (Entry Point)"
report "  - Artifact Registry (Container Registry)"
report "  - Secret Manager (Credentials)"
report ""

report "Security Features:"
report "  - Workload Identity Federation (No long-lived keys)"
report "  - OIDC Token-based authentication"
report "  - Least-privilege service accounts"
report "  - Encrypted secrets in Secret Manager"
report ""

report "=========================================="

echo "Metrics saved to metrics.txt (available as artifact)"
