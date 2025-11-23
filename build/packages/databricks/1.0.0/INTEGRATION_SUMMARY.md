# Databricks Elastic Integration - Summary

This integration package has been created following the Elastic Integration guidelines and is ready for deployment.

## What Was Created

### Package Structure

```
databricks/
├── manifest.yml                          # Main package manifest
├── changelog.yml                         # Version history
├── init.sh                               # Databricks cluster init script (copied from parent)
├── docs/
│   ├── README.md                         # User-facing documentation
│   ├── setup.md                          # Detailed setup guide
│   └── troubleshooting.md                # Troubleshooting guide
├── img/
│   ├── databricks-logo.svg               # Package icon
│   └── databricks-jobs-dashboard.png     # Dashboard screenshot placeholder
├── kibana/
│   └── dashboard/
│       └── databricks-jobs-overview.json # Kibana dashboard definition
├── data_stream/
│   └── job_runs/
│       ├── manifest.yml                  # Data stream configuration
│       ├── agent/
│       │   └── stream/
│       │       └── httpjson.yml.hbs      # Agent configuration template
│       ├── elasticsearch/
│       │   ├── ingest_pipeline/
│       │   │   └── default.yml           # Ingest pipeline with cluster ID extraction
│       │   └── index_template.yml        # Index template with custom mappings
│       └── fields/
│           └── fields.yml                # Field definitions
└── _dev/
    └── build/
        ├── build.yml                     # Build configuration
        └── docs/
            └── README.md                 # Development documentation
```

## Key Features

### 1. Job Runs Monitoring
- **Data Stream**: `logs-databricks.job_runs-*`
- **Input Type**: httpjson
- **API**: Databricks Jobs API v2.2 (`/api/2.2/jobs/runs/list`)
- **Polling Interval**: Configurable (default: 5 minutes)
- **Lookback Period**: Configurable (default: 5 hours)

### 2. Smart Cluster ID Extraction
The ingest pipeline includes intelligent cluster ID extraction logic:
- Extracts from `job.cluster_instance.cluster_id` (run-level)
- Falls back to `job.tasks.cluster_instance.cluster_id` (task-level)
- Defaults to "Serverless" if no cluster is found
- Supports serverless compute jobs automatically

### 3. Custom Index Template
Priority 200 template with:
- Date field mappings for `job.start_time`, `job.end_time`
- Date field mappings for `job.tasks.start_time`, `job.tasks.end_time`
- Keyword mappings for IDs (`job_id`, `job_run_id`, `run_id`, etc.)
- Standard index mode
- Composed of ECS and logs component templates

### 4. Data Processing Pipeline
The ingest pipeline includes:
- Cluster ID extraction script (Painless)
- ECS field mapping
- Event categorization
- Event outcome determination (success/failure/unknown)
- Duration calculation
- Cloud provider detection (AWS/Azure/GCP)
- User field extraction
- Timestamp normalization

### 5. Field Mappings
Complete field definitions for:
- Job metadata (IDs, names, types)
- Job state and status information
- Timing information (start, end, duration)
- Task information (nested)
- User information
- Cluster information
- ECS standard fields

## Configuration Variables

### Required
- `databricks_host`: Workspace URL
- `databricks_token`: Access token (secret)

### Optional
- `request_interval`: Poll frequency (default: 5m)
- `lookback_period`: Historical data window (default: 5h)

## Installation

1. **Build the Package** (optional):
   ```bash
   elastic-package build
   ```
   Output: `build/packages/databricks-1.0.0.zip`

2. **Install in Kibana**:
   - Upload the ZIP file via Fleet UI
   - Or place in Kibana's package directory
   - Or publish to a custom package registry

3. **Configure**:
   - Add integration in Fleet
   - Provide Databricks credentials
   - Assign to an agent policy
   - Deploy to agents

## Testing

### Manual Testing
1. Verify API access:
   ```bash
   curl -H "Authorization: Bearer YOUR_TOKEN" \
        "https://YOUR_HOST/api/2.2/jobs/runs/list?limit=1"
   ```

2. Check data in Discover:
   - Index pattern: `logs-*`
   - Filter: `data_stream.dataset: databricks.job_runs`

3. Verify cluster ID extraction:
   - Check `databricks.cluster_id` field
   - Should show actual cluster IDs or "Serverless"

### Package Validation
```bash
# Format check
elastic-package format

# Lint check
elastic-package lint

# Build
elastic-package build
```

## Dashboards

### Databricks - Jobs Monitoring (`databricks-jobs-monitoring.ndjson`)

A comprehensive dashboard with 9 saved objects:
- **1 Main Dashboard** with 8 panels and 4 control filters
- **6 Lens Visualizations**:
  - Success Runs (green metric)
  - Failed Runs (red metric)
  - Canceled Runs (gray metric)
  - Total Runs (white metric)
  - Job Runs Bar Chart (stacked, color-coded by status)
  - Job Runs Detail Table (sortable, filterable, color-coded)
- **2 TSVB Visualizations**:
  - Databricks Logo (branding)
  - Header Title Banner

**Interactive Features**:
- Control filters: Job Name, Job ID, Job Run ID, Cluster ID
- Time range selector
- Click-to-filter on visualizations
- Sortable and searchable table
- Color-coded status indicators
- Human-readable duration formatting

**Data Fields Used**:
- `job.job_run_id`, `job.run_name`, `job.job_id`
- `job.state.result_state` (SUCCESS/FAILED/CANCELED)
- `job.start_time`, `job.end_time`, `job.run_duration`
- `job.creator_user_name`
- `databricks.cluster_id` (including "Serverless")
- `job.status.termination_details.code`

See `DASHBOARD_INFO.md` for complete dashboard documentation.

## API Endpoints Used

- `GET /api/2.2/jobs/runs/list`
  - Parameters: `expand_tasks=true`, `start_time_from`, `page_token`
  - Returns: Job run information with task details

## Field Naming Conventions

- **ECS Fields**: `event.*`, `cloud.*`, `user.*`, `related.*`
- **Databricks Fields**: `databricks.*` (cluster_id, workspace_id)
- **Job Fields**: `job.*` (all job-related data)
- **Data Stream**: `data_stream.*` (type, dataset, namespace)

## Compatibility

- **Elastic Stack**: 8.8.0+
- **Databricks**: All versions with Jobs API 2.2
- **Clouds**: AWS, Azure, GCP
- **Job Types**: Cluster-based and serverless

## Next Steps

1. **Customize Dashboards**: Import the NDJSON dashboards from the parent directory for full visualization
2. **Set Up Alerts**: Create detection rules for failed jobs
3. **Add More Data Streams**: Extend with cluster metrics if needed (currently removed per requirements)
4. **Test with Real Data**: Deploy to a test environment with active Databricks jobs
5. **Document Custom Fields**: Add any organization-specific field documentation

## Notes

- The integration focuses solely on job_runs data stream (cluster_metrics removed per requirements)
- Ingest pipeline includes the specific cluster ID extraction logic provided
- Index template uses the exact mappings specified
- All timestamps are properly typed as date fields
- The package is ready for production use after testing

