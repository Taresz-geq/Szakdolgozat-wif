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

# Pipeline info - GitHub Actions environment variables
report "Pipeline Information:"
report "  Workflow Run ID: $GITHUB_RUN_ID"
report "  Workflow URL: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
report "  Branch: $GITHUB_REF_NAME"
report "  Commit: $(echo $GITHUB_SHA | cut -c1-7)"
report "  Repository: $GITHUB_REPOSITORY"
report ""

# Check if GITHUB_TOKEN is set
if [ -z "$GITHUB_TOKEN" ]; then
  report "Note: Set GITHUB_TOKEN variable for detailed metrics"
  report "(Automatically provided by GitHub Actions)"
  report ""
else
  # Debug: Log API endpoint (without exposing token)
  echo "DEBUG: Fetching from API /repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" >&2

  # Get workflow run details via GitHub API with better error handling
  PIPELINE_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    --header "Authorization: Bearer $GITHUB_TOKEN" \
    --header "Accept: application/vnd.github+json" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID")

  HTTP_STATUS=$(echo "$PIPELINE_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
  PIPELINE_DATA=$(echo "$PIPELINE_RESPONSE" | sed '/HTTP_STATUS:/d')

  echo "DEBUG: Workflow API returned status: $HTTP_STATUS" >&2

  # Check if API call was successful
  if [ "$HTTP_STATUS" = "200" ] && [ -n "$PIPELINE_DATA" ] && echo "$PIPELINE_DATA" | jq empty >/dev/null 2>&1; then
    DURATION=$(echo "$PIPELINE_DATA" | jq -r '((.updated_at | fromdateiso8601) - (.created_at | fromdateiso8601)) // null' 2>/dev/null)
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

    # Get job details from GitHub Actions
    report "Job Performance:"
    JOBS_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
      --header "Authorization: Bearer $GITHUB_TOKEN" \
      --header "Accept: application/vnd.github+json" \
      --header "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/jobs")

    JOBS_HTTP_STATUS=$(echo "$JOBS_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
    JOBS_DATA=$(echo "$JOBS_RESPONSE" | sed '/HTTP_STATUS:/d')

    echo "DEBUG: Jobs API returned status: $JOBS_HTTP_STATUS" >&2
    echo "DEBUG: Jobs data length: ${#JOBS_DATA}" >&2

    if [ "$JOBS_HTTP_STATUS" = "200" ]; then
      # Validate JSON
      if echo "$JOBS_DATA" | jq empty >/dev/null 2>&1; then
        JOBS=$(echo "$JOBS_DATA" | jq '.jobs' 2>/dev/null)
        JOB_COUNT=$(echo "$JOBS" | jq 'length' 2>/dev/null)
        echo "DEBUG: Found $JOB_COUNT jobs" >&2

        if [ "$JOB_COUNT" -gt 0 ]; then
          # Display all jobs with their status
          report "  Jobs executed:"
          echo "$JOBS" | jq -r '.[] |
            (if (.completed_at != null and .started_at != null) then (((.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601)) | tostring) else "N/A" end) as $duration |
            "  - \(.name): \($duration)s (\(.conclusion // .status))"' 2>/dev/null | tee -a metrics.txt

          report ""

          # Show completed jobs sorted by duration
          COMPLETED_JOBS=$(echo "$JOBS" | jq '[.[] | select(.status == "completed")]' 2>/dev/null)
          COMPLETED_COUNT=$(echo "$COMPLETED_JOBS" | jq 'length' 2>/dev/null)

          if [ "$COMPLETED_COUNT" -gt 0 ]; then
            report "  Completed jobs (sorted by duration):"
            echo "$COMPLETED_JOBS" | jq -r '.[] |
              (if (.completed_at != null and .started_at != null) then (((.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601))) else 0 end) as $duration |
              "\($duration)\t\(.name)\t\(.conclusion)"' 2>/dev/null | \
              sort -nr | \
              awk '{printf "  - %s: %ss (%s)\n", $2, $1, $3}' | tee -a metrics.txt
            report ""
          fi

          report "Authentication Method: Workload Identity Federation (Keyless)"
          report "Cloud Provider: Google Cloud Platform"
          report "CI/CD Platform: GitHub Actions"
          report ""

          # Calculate statistics
          TOTAL_JOB_TIME=$(echo "$JOBS" | jq '[.[] | select(.completed_at != null and .started_at != null) | ((.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601))] | add // 0' 2>/dev/null)
          SUCCESSFUL_JOBS=$(echo "$JOBS" | jq '[.[] | select(.conclusion == "success")] | length' 2>/dev/null)
          FAILED_JOBS=$(echo "$JOBS" | jq '[.[] | select(.conclusion == "failure")] | length' 2>/dev/null)
          RUNNING_JOBS=$(echo "$JOBS" | jq '[.[] | select(.status == "in_progress")] | length' 2>/dev/null)

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
        report "  - Verify GITHUB_TOKEN is valid"
        report "  - Check token hasn't expired"
      elif [ "$JOBS_HTTP_STATUS" = "403" ]; then
        report "  Error: Access forbidden (HTTP 403)"
        report "  - Token may not have permission to access this repository"
      elif [ "$JOBS_HTTP_STATUS" = "404" ]; then
        report "  Error: Workflow run not found (HTTP 404)"
      else
        report "  Error: API request failed (HTTP status: $JOBS_HTTP_STATUS)"
      fi
      echo "DEBUG: Jobs response: $JOBS_DATA" >&2
      report ""
    fi
  else
    report "Pipeline Duration:"
    report "  Total time: N/A seconds ( minutes)"
    report ""

    report "Job Performance:"
    report "  Unable to fetch workflow run details (HTTP status: $HTTP_STATUS)"

    if [ "$HTTP_STATUS" = "401" ]; then
      report "  - Token authentication failed"
      report "  - Verify GITHUB_TOKEN is valid"
    elif [ "$HTTP_STATUS" = "403" ]; then
      report "  - Access forbidden - check token permissions"
    elif [ "$HTTP_STATUS" = "404" ]; then
      report "  - Workflow run not found - verify repository and run ID"
    elif [ -z "$HTTP_STATUS" ]; then
      report "  - No response from API - check network connectivity"
    fi

    echo "DEBUG: Workflow response: $PIPELINE_DATA" >&2
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
