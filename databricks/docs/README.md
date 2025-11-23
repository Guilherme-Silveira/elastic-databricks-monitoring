# Databricks Integration

## Overview

The Databricks integration allows you to monitor your Databricks clusters and job runs. It collects:

- **Job Runs**: Information about Databricks job executions including status, duration, and metadata
- **Apache Spark Metrics**: JMX metrics from Spark driver and executors via Jolokia agent
- **Spark Logs**: Driver and executor logs from Databricks clusters

## Requirements

### For Job Runs Monitoring

- Databricks workspace URL
- Databricks Personal Access Token or Service Principal token with permissions to access the Jobs API
- Elastic Agent with httpjson input support

### For Cluster Monitoring (Spark Metrics and Logs)

- Databricks cluster with init script to install:
  - Jolokia JVM agent for JMX metrics
  - Elastic Agent for log and metric collection
- Network access from Elastic Agent to Jolokia endpoint (port 7777 by default)

## Setup

### Step 1: Configure Job Runs Collection

1. Create a Databricks Personal Access Token:
   - Go to User Settings > Access Tokens in your Databricks workspace
   - Generate a new token and save it securely

2. Add the Databricks integration in Kibana:
   - Navigate to Management > Integrations
   - Search for "Databricks" and click on it
   - Click "Add Databricks"
   - Configure the following fields:

#### Configuration Fields

##### Databricks Host
- **Description**: The full URL of your Databricks workspace
- **Required**: Yes
- **Format**: `https://your-workspace.cloud.databricks.com` (AWS) or `https://adb-<workspace-id>.<region>.azuredatabricks.net` (Azure) or `https://<workspace-id>.gcp.databricks.com` (GCP)
- **Example**: `https://my-company.cloud.databricks.com`
- **Notes**: 
  - Do not include trailing slashes
  - Must be a valid HTTPS URL
  - The integration automatically detects the cloud provider (AWS, Azure, GCP) from the host URL

##### Access Token
- **Description**: Databricks Personal Access Token (PAT) or Service Principal token for API authentication
- **Required**: Yes
- **Format**: String token (typically starts with `dapi...` for PAT)
- **Permissions Required**: 
  - Read access to Jobs API (`jobs:read`)
  - Recommended: Use a service principal with minimal required permissions
- **Security**: 
  - Token is stored securely in Kibana and marked as a secret field
  - Never log or display the token value
  - Rotate tokens regularly according to your security policy
- **How to Create**:
  1. Go to **User Settings** > **Developer** > **Access Tokens** in Databricks
  2. Click **Generate New Token**
  3. Set a descriptive comment (e.g., "Elastic Monitoring")
  4. Set an appropriate lifetime (or leave blank for no expiration)
  5. Copy and save the token immediately (it won't be shown again)

##### Request Interval
- **Description**: How frequently the integration polls the Databricks Jobs API for new job run data
- **Required**: Yes
- **Default**: `5m` (5 minutes)
- **Format**: Duration string (e.g., `1m`, `5m`, `10m`, `1h`)
- **Recommended Values**:
  - **High-frequency jobs** (running every few minutes): `1m` - `3m`
  - **Standard monitoring** (jobs running hourly or daily): `5m` - `10m`
  - **Low-frequency jobs** (occasional runs): `15m` - `30m`
- **Considerations**:
  - Shorter intervals provide more real-time visibility but increase API calls
  - Databricks API has rate limits; avoid intervals shorter than 1 minute
  - Must be shorter than or equal to the lookback period
  - Balance between data freshness and API usage

##### Lookback Period
- **Description**: How far back in time to search for job runs on each polling cycle
- **Required**: Yes
- **Default**: `5h` (5 hours)
- **Format**: Duration string (e.g., `30m`, `1h`, `5h`, `24h`)
- **⚠️ Important Configuration**:
  - **Set this to the maximum expected job timeout/duration in your environment**
  - This ensures the integration captures the complete execution history of long-running jobs
  - Example: If your longest job takes 8 hours to complete, set this to `8h` or higher (e.g., `12h` for safety margin)
- **Duplicate Handling**:
  - The integration automatically handles duplicate records for terminated jobs within the lookback window
  - Jobs with `status.state: TERMINATED` are tracked and deduplicated based on `job_run_id`
  - This prevents redundant data ingestion while ensuring no runs are missed
- **Recommended Values by Use Case**:
  - **Short jobs** (minutes to 1 hour): `2h` - `5h` (provides buffer for delayed job starts)
  - **Medium jobs** (1-4 hours): `6h` - `12h`
  - **Long jobs** (4-12 hours): `12h` - `24h`
  - **Very long jobs** (12+ hours): Match or exceed your longest job duration
- **Considerations**:
  - Lookback period must be greater than or equal to the request interval
  - Longer lookback periods increase the initial query size but don't significantly impact performance due to deduplication
  - If jobs are missed, increase this value
  - Consider job retry behavior - retries may extend total job execution time
- **Example Configuration**:
  ```
  Request Interval: 5m
  Lookback Period: 12h
  
  This configuration:
  - Polls API every 5 minutes
  - Looks back 12 hours on each poll
  - Captures jobs that started up to 12 hours ago
  - Safely handles jobs running up to 12 hours
  ```

### Step 2: Configure Cluster Monitoring (Optional)

This step is only required if you want to collect Spark metrics and logs from your Databricks clusters using the init script.

#### 2.1. Store the Init Script

Upload the init script (`init.sh`) to a supported location. Databricks recommends using [Unity Catalog volumes](https://docs.databricks.com/aws/en/ingestion/file-upload/upload-to-volume), workspace files, or cloud object storage depending on your Databricks Runtime version and cluster access mode. See [Databricks init scripts documentation](https://docs.databricks.com/aws/en/init-scripts/#where-can-init-scripts-be-installed) for detailed recommendations.

**Recommended locations by environment:**
- **Databricks Runtime 13.3 LTS and above with Unity Catalog**: Store in Unity Catalog volumes
- **Databricks Runtime 11.3 LTS and above without Unity Catalog**: Store as workspace files (500 MB limit)
- **Databricks Runtime 10.4 LTS and below**: Store in cloud object storage (S3, Azure Blob, GCS)

#### 2.2. Configure Databricks Secrets (Recommended)

To securely store your Elasticsearch API key, use [Databricks Secrets](https://docs.databricks.com/aws/en/security/secrets/):

1. Create a secret scope:
   ```bash
   databricks secrets create-scope elastic-monitoring
   ```

2. Store your Elasticsearch API key:
   ```bash
   databricks secrets put-secret elastic-monitoring elasticsearch-api-key
   ```
   When prompted, paste your Elasticsearch API key.

#### 2.3. Configure Cluster Settings

1. **Add Init Script**:
   - In the cluster configuration, go to **Advanced Options** > **Init Scripts**
   - Click **Add** and select your init script location:
     - **Volumes**: `/Volumes/<catalog>/<schema>/<volume>/init.sh`
     - **Workspace files**: `/Workspace/Users/<username>/init.sh`
     - **Cloud storage**: `s3://your-bucket/path/init.sh` (or `abfss://`, `gs://`)

2. **Configure Environment Variables**:
   
   Go to **Advanced Options** > **Spark** > **Environment Variables** and add:
   
   ```bash
   ELASTIC_AGENT_VERSION=8.8.0
   ARCH=linux-x86_64
   ELASTICSEARCH_HOST=https://your-elasticsearch-host:9200
   ```
   
   **Using Databricks Secrets (Recommended)**:
   ```bash
   ELASTICSEARCH_API_KEY={{secrets/elastic-monitoring/elasticsearch-api-key}}
   ```
   
   **Or using plain text** (not recommended for production):
   ```bash
   ELASTICSEARCH_API_KEY=your-api-key-here
   ```

3. **Configure Spark Settings for Jolokia**:
   
   Go to **Advanced Options** > **Spark** > **Spark Config** and add:
   
   ```
   spark.driver.extraJavaOptions -javaagent:/opt/jolokia/jolokia-agent-jvm-javaagent.jar=config=/databricks/spark/conf/jolokia-master.properties
   spark.executor.extraJavaOptions -javaagent:/opt/jolokia/jolokia-agent-jvm-javaagent.jar=config=/databricks/spark/conf/jolokia-master.properties
   ```
   
   These settings enable Jolokia JVM agent on both Spark driver and executor nodes for JMX metrics collection.

4. **Start or Restart the Cluster**:
   - Save the cluster configuration
   - Start a new cluster or restart an existing one
   - The init script will run automatically on all cluster nodes

#### 2.4. Verify Init Script Execution

The init script will:
- Install and configure Jolokia agent on port 7777
- Install Elastic Agent
- Configure collection of Spark driver and executor logs
- Set up system metrics collection (CPU, memory, disk, network)
- Configure JMX metric collection via Jolokia

To verify the init script ran successfully:
1. Check cluster event logs for init script execution status
2. Verify Jolokia is running: `curl http://localhost:7777/jolokia/version`
3. Check Elastic Agent status on cluster nodes
4. Review data flowing into Elasticsearch indices:
   - `logs-spark.driver-*`
   - `logs-spark.executor-*`
   - `metrics-system.*-*`
   - `metrics-apache_spark.*-*`

## Data Streams

### job_runs

**Data Stream**: `logs-databricks.job_runs-*`

The `job_runs` data stream collects information about Databricks job executions through the Jobs API.

**Job Identification Fields**:
- `job.job_id`: The canonical identifier of the job
- `job.job_run_id`: The canonical identifier of the run
- `job.run_id`: The run identifier
- `job.original_attempt_run_id`: The original attempt run identifier
- `job.run_number`: The sequence number of this run attempt for the job
- `job.number_in_job`: The sequence number of this run attempt for the job (as keyword)
- `job.run_name`: The name of the job run
- `job.run_page_url`: The URL of the run page in the Databricks UI
- `job.run_type`: The type of run (JOB_RUN, WORKFLOW_RUN, SUBMIT_RUN)

**Job State Fields**:
- `job.state.life_cycle_state`: The life cycle state (PENDING, RUNNING, TERMINATING, TERMINATED, SKIPPED, INTERNAL_ERROR)
- `job.state.result_state`: The result state (SUCCESS, FAILED, CANCELED, TIMEDOUT)
- `job.state.state_message`: A descriptive message for the current state
- `job.state.user_cancelled_or_timedout`: Whether the run was cancelled by the user or timed out

**Job Status Fields**:
- `job.status.state`: The current state of the run
- `job.status.termination_details.code`: The termination code
- `job.status.termination_details.type`: The type of termination

**Timing and Duration Fields** (all durations in milliseconds):
- `job.start_time`: The time at which this run was started
- `job.end_time`: The time at which this run ended
- `job.run_duration`: The duration of the run in milliseconds
- `job.setup_duration`: The time it took to set up the cluster
- `job.execution_duration`: The time it took to execute the commands
- `job.cleanup_duration`: The time it took to terminate the cluster
- `job.queue_duration`: The time the run was queued

**Task Fields**:
- `job.tasks.run_id`: The ID of the task run
- `job.tasks.start_time`: The time at which the task was started
- `job.tasks.end_time`: The time at which the task ended
- `job.tasks.setup_duration`: The time in milliseconds it took to set up the task
- `job.tasks.execution_duration`: The time in milliseconds it took to execute the task
- `job.tasks.cleanup_duration`: The time in milliseconds it took to clean up the task
- `job.tasks.queue_duration`: The time in milliseconds the task was queued

**Task Detail Fields**:
- `job.task.run_id`: The ID of the task run
- `job.task.task_key`: The unique key of the task
- `job.task.description`: An optional description of the task
- `job.task.state.life_cycle_state`: The life cycle state of the task
- `job.task.state.result_state`: The result state of the task
- `job.task.start_time`: The time at which this task was started
- `job.task.end_time`: The time at which this task ended
- `job.task.execution_duration`: The time in milliseconds it took to execute the task

**User and Trigger Fields**:
- `job.creator_user_name`: The creator user name
- `job.trigger`: The trigger that started this run (ONE_TIME, PERIODIC, RETRY, RUN_JOB_TASK)

**Schedule Fields**:
- `job.schedule.quartz_cron_expression`: A Cron expression using Quartz syntax
- `job.schedule.timezone_id`: A Java timezone ID
- `job.schedule.pause_status`: Whether the schedule is paused or not

**Databricks Fields**:
- `databricks.cluster_id`: The ID of the cluster used by the run (or 'Serverless' for serverless jobs)
- `databricks.cluster_name`: The name of the cluster
- `databricks.workspace_id`: The ID of the Databricks workspace

**ECS Event Fields**:
- `event.id`: Unique ID to describe the event (same as job_run_id)
- `event.kind`: Event kind (event)
- `event.type`: Event type
- `event.category`: Event category
- `event.module`: Name of the module (databricks)
- `event.dataset`: Name of the dataset (databricks.job_runs)
- `event.start`: The start time of the job run
- `event.end`: The end time of the job run
- `event.duration`: Duration of the event in nanoseconds
- `event.outcome`: The outcome of the job run (success, failure, unknown)

**User and Cloud Fields**:
- `user.name`: Short name or login of the user
- `cloud.provider`: Name of the cloud provider (aws, azure, gcp)
- `related.user`: All the user names or other user identifiers seen on the event

**Data Stream Fields**:
- `data_stream.type`: Data stream type (logs)
- `data_stream.dataset`: Data stream dataset (databricks.job_runs)
- `data_stream.namespace`: Data stream namespace
- `@timestamp`: Event timestamp

### cluster_metrics

**Data Streams**:
- `logs-spark.driver-*` - Spark driver logs
- `logs-spark.executor-*` - Spark executor logs  
- `metrics-system.*-*` - System metrics (CPU, memory, disk, network, etc.)
- `metrics-apache_spark.*-*` - Apache Spark JMX metrics

The `cluster_metrics` data stream collects Apache Spark JMX metrics via Jolokia agent and system logs from Databricks clusters.

**Metric Sets**:
- **Driver metrics**: Job statistics, stage statistics, memory usage, DAG scheduler info
- **Executor metrics**: Bytes read/written, shuffle statistics, memory usage, GC metrics

**Spark Metric Fields**:
- `apache_spark.driver.*`: Spark driver metrics
- `apache_spark.executor.*`: Spark executor metrics

**Databricks Fields**:
- `databricks.cluster_id`: The ID of the cluster
- `databricks.cluster_name`: The name of the cluster
- `databricks.workspace_id`: The ID of the Databricks workspace
- `databricks.node_role`: Role (Driver or Executor)
- `databricks.container_ip`: The IP address of the container
- `databricks.instance_type`: The instance type of the cluster node
- `databricks.is_job_cluster`: Whether the cluster is a job cluster or interactive cluster

## Dashboards

This integration includes two pre-built dashboards:

### Databricks Jobs Monitoring

Visualizes job run statistics including:
- Total, successful, failed, and canceled runs
- Job run timeline by status
- Detailed job run table with duration, timestamps, and status
- Job run trends over time

### Databricks Cluster Monitoring

Visualizes Apache Spark metrics including:
- Spark application metrics
- Driver and executor statistics
- Memory and CPU usage
- JVM metrics and garbage collection

## Troubleshooting

### Job Runs Not Appearing

1. Verify your Databricks host URL is correct
2. Check that the access token has permission to access the Jobs API
3. Review Elastic Agent logs for API connection errors
4. Ensure the lookback period covers the time range of interest

### Cluster Metrics Not Appearing

1. Verify the init script ran successfully (check cluster event logs)
2. Confirm Jolokia is running on port 7777:
   ```bash
   curl http://localhost:7777/jolokia/version
   ```
3. Check that Elastic Agent is installed and running on the cluster
4. Review Elastic Agent logs for connection issues

### Missing Logs

1. Verify Elastic Agent is installed on the cluster nodes
2. Check that log paths are accessible
3. Review Elastic Agent configuration in the init script
4. Ensure proper permissions on log directories

## Compatibility

- Elastic Stack: 8.8.0 or later
- Databricks Runtime: 10.4 LTS or later
- Apache Spark: 3.x
- Jolokia: 2.x

## License

This integration is licensed under the Elastic License 2.0.

