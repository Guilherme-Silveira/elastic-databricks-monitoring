# Databricks Monitoring Integration for Elastic Stack

A comprehensive Elastic Integration package for monitoring Databricks workspaces, job runs, and cluster metrics.

## 📋 Overview

This repository contains a production-ready Elastic Integration that enables complete observability of your Databricks environment by collecting:

- **Job Run Information**: Detailed execution data from the Databricks Jobs API including status, duration, tasks, and metadata
- **Spark Metrics**: JMX metrics from Apache Spark drivers and executors via Jolokia agent
- **Cluster Logs**: Spark driver and executor logs from Databricks clusters
- **System Metrics**: CPU, memory, disk, network metrics from cluster nodes

## ✨ Features

- 🔄 **Automated Job Monitoring**: Continuous polling of Databricks Jobs API with configurable intervals
- 📊 **Pre-built Dashboards**: 2 ready-to-use Kibana dashboards for job runs and cluster metrics
- 🔐 **Secure Configuration**: Support for Databricks Secrets to protect sensitive credentials
- 🎯 **Serverless Detection**: Automatic identification and tagging of serverless job runs
- 📈 **Comprehensive Metrics**: ~75 documented fields covering all aspects of job execution
- 🛡️ **ECS Compliance**: Elastic Common Schema (ECS) field mapping for standardized data structure
- ⚡ **Null-Safe Processing**: Robust ingest pipeline with comprehensive error handling

## 📦 Repository Contents

```
databricks-elastic-monitoring/
├── databricks/                           # Elastic Integration package
│   ├── manifest.yml                      # Package metadata and configuration
│   ├── changelog.yml                     # Version history
│   ├── docs/
│   │   └── README.md                     # Integration documentation (API Reference)
│   ├── data_stream/
│   │   └── job_runs/                     # Job runs data stream
│   │       ├── manifest.yml              # Data stream configuration
│   │       ├── agent/stream/
│   │       │   └── httpjson.yml.hbs      # Elastic Agent httpjson input
│   │       ├── elasticsearch/
│   │       │   └── ingest_pipeline/
│   │       │       └── default.yml       # Ingest pipeline for data processing
│   │       └── fields/
│   │           └── fields.yml            # Field definitions (~75 fields)
│   ├── kibana/
│   │   ├── dashboard/                    # Pre-built dashboards (2 files)
│   │   └── tag/                          # Dashboard tags
│   └── img/
│       └── databricks-logo.svg           # Integration icon
│
├── init.sh                               # Cluster init script for Elastic Agent
├── cluster_monitoring.ndjson             # Cluster monitoring dashboard (NDJSON)
├── jobs_monitoring.ndjson                # Jobs monitoring dashboard (NDJSON)
├── custom_api_integration.json           # Original API integration reference
└── build/
    └── packages/
        └── databricks-1.0.0.zip          # Built integration package
```

## 🚀 Quick Start

### Prerequisites

- Elastic Stack 8.8.0 or later
- Databricks workspace with API access
- Databricks Personal Access Token or Service Principal

### Installation

1. **Build the Integration Package**:
   ```bash
   cd databricks-elastic-monitoring/databricks
   elastic-package build
   ```

2. **Install in Kibana**:
   - Navigate to **Fleet** > **Integrations**
   - Click **Upload integration**
   - Select `build/packages/databricks-1.0.0.zip`
   - Click **Install Databricks assets**

3. **Configure the Integration**:
   - Click **Add Databricks** integration
   - Configure:
     - **Databricks Host**: `https://your-workspace.cloud.databricks.com`
     - **Access Token**: Your Databricks PAT
     - **Request Interval**: `5m` (default)
     - **Lookback Period**: `5h` (default)
   - Assign to an Agent Policy
   - Save and deploy

### Optional: Cluster Monitoring Setup

To collect Spark metrics and logs from Databricks clusters:

1. **Store the Init Script**:
   - Upload `init.sh` to Unity Catalog volumes, workspace files, or cloud storage
   - Recommended locations based on your Databricks Runtime version

2. **Configure Databricks Secrets** (Recommended):
   ```bash
   databricks secrets create-scope elastic-monitoring
   databricks secrets put-secret elastic-monitoring elasticsearch-api-key
   ```

3. **Configure Cluster**:
   - Add init script path
   - Set environment variables (with secrets reference)
   - Add Spark config for Jolokia agent
   - See detailed instructions in `databricks/docs/README.md`

## 📊 Data Streams

The integration creates the following data streams in Elasticsearch:

### Job Runs
- **Index Pattern**: `logs-databricks.job_runs-*`
- **Description**: Databricks job execution data
- **Fields**: ~75 fields including job identification, state, timing, tasks, and ECS fields

### Cluster Metrics & Logs (via init script)
- **Index Pattern**: `logs-spark.driver-*` - Spark driver logs
- **Index Pattern**: `logs-spark.executor-*` - Spark executor logs
- **Index Pattern**: `metrics-system.*-*` - System metrics (CPU, memory, disk, network)
- **Index Pattern**: `metrics-apache_spark.*-*` - Apache Spark JMX metrics

## 📈 Dashboards

The integration includes 2 pre-built dashboards:

### 1. Databricks - Jobs Monitoring
- Total, successful, failed, and canceled job runs
- Job run timeline by status
- Detailed job run table with duration and metadata
- Filters: Job Name, Job ID, Run ID, Cluster ID

### 2. Databricks - Cluster Monitoring
- Spark application metrics
- Driver and executor statistics
- Memory and CPU usage
- JVM metrics and garbage collection

## 🔧 Development

### Building the Integration

```bash
cd databricks/
elastic-package build
```

### Validation

```bash
# Lint the package
elastic-package lint

# Run tests (if configured)
elastic-package test
```

### Structure Requirements

The integration follows the [Elastic Packages specification](https://github.com/elastic/elastic-package):
- Package manifest in `manifest.yml`
- Data stream configurations in `data_stream/*/manifest.yml`
- Field definitions in `fields/fields.yml`
- Ingest pipelines in `elasticsearch/ingest_pipeline/`
- Dashboards in `kibana/dashboard/` (exported "by value")

## 📚 Documentation

Detailed documentation is available in:
- **Integration Docs**: `databricks/docs/README.md` - Complete setup and field reference
- **Integration Summary**: `databricks/INTEGRATION_SUMMARY.md` - Feature overview
- **Changelog**: `databricks/changelog.yml` - Version history

## 🔐 Security Best Practices

1. **Use Databricks Secrets**: Store Elasticsearch API keys in Databricks Secrets instead of environment variables
2. **Restrict Access Tokens**: Use service principals with minimal required permissions
3. **Enable Unity Catalog**: For better access control and data governance
4. **Review Init Scripts**: Ensure init scripts follow your organization's security policies

## 🐛 Troubleshooting

### Job Runs Not Appearing
1. Verify Databricks host URL is correct
2. Check access token has Jobs API permissions
3. Review Elastic Agent logs for API errors
4. Ensure lookback period covers the time range

### Cluster Metrics Not Appearing
1. Check init script execution in cluster event logs
2. Verify Jolokia is running: `curl http://localhost:7777/jolokia/version`
3. Confirm Elastic Agent is installed and running
4. Review Agent logs for connection issues

## 🔗 References

- [Databricks Jobs API](https://docs.databricks.com/api/workspace/jobs)
- [Databricks Init Scripts](https://docs.databricks.com/aws/en/init-scripts/)
- [Databricks Secrets](https://docs.databricks.com/aws/en/security/secrets/)
- [Elastic Integrations](https://www.elastic.co/docs/extend/integrations)
- [elastic-package CLI](https://github.com/elastic/elastic-package)

## 📄 License

This integration is licensed under the Elastic License 2.0.

## 🤝 Contributing

Contributions are welcome! Please ensure:
- All fields are documented in `fields.yml` and `docs/README.md`
- Ingest pipelines include error handling
- Dashboards are exported "by value" with embedded visualizations
- Package builds successfully with `elastic-package build`

---

**Version**: 1.0.0  
**Compatibility**: Elastic Stack 8.8.0+  
**Databricks Runtime**: 10.4 LTS and above
