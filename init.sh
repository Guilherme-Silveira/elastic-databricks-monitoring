#!/bin/bash
# INIT SCRIPT for Databricks cluster to install and configure Jolokia Agent for Apache Spark Metrics (Elastic integration)

JOL_VERSION="2.2.9"
JOL_JAR="jolokia-agent-jvm-${JOL_VERSION}-javaagent.jar"
JOL_URL="https://search.maven.org/remotecontent?filepath=org/jolokia/jolokia-agent-jvm/${JOL_VERSION}/${JOL_JAR}"
SPARK_CONF_DIR="/databricks/spark/conf"
INSTALL_DIR="/opt/jolokia"

mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

# Download Jolokia agent
wget -O "${INSTALL_DIR}/jolokia-agent-jvm-javaagent.jar" "${JOL_URL}"

# Jolokia properties for master/worker (customize ports if running multiple on same node!)
cat > "${SPARK_CONF_DIR}/jolokia-master.properties" <<EOF
host=0.0.0.0
port=7777
agentContext=/jolokia
backlog=100
policyLocation=file://${SPARK_CONF_DIR}/jolokia.policy
historyMaxEntries=10
debug=false
debugMaxEntries=100
maxDepth=15
maxCollectionSize=1000
maxObjects=0
EOF

# Jolokia agent security policy
cat > "${SPARK_CONF_DIR}/jolokia.policy" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<restrict>
<http>
<method>get</method>
<method>post</method>
</http>
<commands>
<command>read</command>
<command>list</command>
</commands>
</restrict>
EOF

echo '*.sink.jmx.class=org.apache.spark.metrics.sink.JmxSink' >> ${SPARK_CONF_DIR}/metrics.properties
echo '*.source.jvm.class=org.apache.spark.metrics.source.JvmSource' >> ${SPARK_CONF_DIR}/metrics.properties
echo 'master.source.master.class=org.apache.spark.metrics.source.MasterSource' >> ${SPARK_CONF_DIR}/metrics.properties
echo 'worker.source.worker.class=org.apache.spark.metrics.source.WorkerSource' >> ${SPARK_CONF_DIR}/metrics.properties

echo "Jolokia agent for Spark configured for Databricks cluster."

# ------- INSTALL ELASTIC AGENT -------
cd /tmp
curl -L -O "https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${ELASTIC_AGENT_VERSION}-${ARCH}.tar.gz"
tar xzvf "elastic-agent-${ELASTIC_AGENT_VERSION}-${ARCH}.tar.gz"
cd "elastic-agent-${ELASTIC_AGENT_VERSION}-${ARCH}"

# ------- CONFIGURE ELASTIC AGENT -------
cat > elastic-agent.yml <<EOF
outputs:
  default:
    type: elasticsearch
    hosts: ['$ELASTICSEARCH_HOST']
    api_key: '$ELASTICSEARCH_API_KEY'

inputs:
  - type: filestream
    id: databricks-spark-logs-1
    use_output: default
    data_stream.namespace: databricks
    streams:
      - data_stream.dataset: spark.driver
        id: databricks-spark-driver-logs-1
        paths:
          - /databricks/driver/logs/stdout*
          - /databricks/driver/logs/stderr*
          - /databricks/driver/logs/*.log
          - /databricks/driver/logs/*.out
        parsers:
          - multiline:
              type: pattern
              # Alternate example for logs that start with "YY/MM/DD HH:MM:SS"
              pattern: '^\d{2}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}'
              negate: true
              match: after
              max_lines: 1000
              timeout: 10s
        exclude_files:
          - '*.gz'
        processors:
          - script:
              lang: javascript
              source: >
                function process(event) {
                  // DB_IS_DRIVER is provided by Databricks as "TRUE"/"FALSE".
                  var isDriver = "${DB_IS_DRIVER}" === "TRUE";
                  event.Put("databricks.node_role", isDriver ? "Driver" : "Executor");
                }
          - add_fields:
              target: databricks
              fields:
                cluster_id: ${DB_CLUSTER_ID}
                container_ip: ${DB_CONTAINER_IP}
                instance_type: ${DB_INSTANCE_TYPE}
                cluster_name: ${DB_CLUSTER_NAME}
                is_job_cluster: ${DB_IS_JOB_CLUSTER}
      - data_stream.dataset: spark.executor
        id: databricks-spark-executor-logs-1
        paths:
          - /databricks/spark/work/*/*/stdout*
          - /databricks/spark/work/*/*/stderr*
          - /databricks/spark/work/*/*/log4j-*.log
        parsers:
          - multiline:
              type: pattern
              # Alternate example for logs that start with "YY/MM/DD HH:MM:SS"
              pattern: '^\d{2}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}'
              negate: true
              match: after
              max_lines: 1000
              timeout: 10s
        exclude_files:
          - '*.gz'
        processors:
          - script:
              lang: javascript
              source: >
                function process(event) {
                  // DB_IS_DRIVER is provided by Databricks as "TRUE"/"FALSE".
                  var isDriver = "${DB_IS_DRIVER}" === "TRUE";
                  event.Put("databricks.node_role", isDriver ? "Driver" : "Executor");
                }
          - add_fields:
              target: databricks
              fields:
                cluster_id: ${DB_CLUSTER_ID}
                container_ip: ${DB_CONTAINER_IP}
                instance_type: ${DB_INSTANCE_TYPE}
                cluster_name: ${DB_CLUSTER_NAME}
                is_job_cluster: ${DB_IS_JOB_CLUSTER}
  - type: system/metrics
    id: databricks-node-metrics-1
    data_stream.namespace: databricks
    use_output: default
    streams:
      - metricsets:
        - cpu
        # Dataset name must conform to the naming conventions for Elasticsearch indices, cannot contain dashes (-), and cannot exceed 100 bytes
        data_stream.dataset: system.cpu
        processors:
        - script:
            lang: javascript
            source: >
              function process(event) {
                // DB_IS_DRIVER is provided by Databricks as "TRUE"/"FALSE".
                var isDriver = "${DB_IS_DRIVER}" === "TRUE";
                event.Put("databricks.node_role", isDriver ? "Driver" : "Executor");
              }
        - add_fields:
            target: databricks
            fields:
              cluster_id: ${DB_CLUSTER_ID}
              container_ip: ${DB_CONTAINER_IP}
              instance_type: ${DB_INSTANCE_TYPE}
              cluster_name: ${DB_CLUSTER_NAME}
              is_job_cluster: ${DB_IS_JOB_CLUSTER}
      - metricsets:
        - memory
        data_stream.dataset: system.memory
        processors:
        - script:
            lang: javascript
            source: >
              function process(event) {
                // DB_IS_DRIVER is provided by Databricks as "TRUE"/"FALSE".
                var isDriver = "${DB_IS_DRIVER}" === "TRUE";
                event.Put("databricks.node_role", isDriver ? "Driver" : "Executor");
              }
        - add_fields:
            target: databricks
            fields:
              cluster_id: ${DB_CLUSTER_ID}
              container_ip: ${DB_CONTAINER_IP}
              instance_type: ${DB_INSTANCE_TYPE}
              cluster_name: ${DB_CLUSTER_NAME}
              is_job_cluster: ${DB_IS_JOB_CLUSTER}
      - metricsets:
        - network
        data_stream.dataset: system.network
        processors:
        - script:
            lang: javascript
            source: >
              function process(event) {
                // DB_IS_DRIVER is provided by Databricks as "TRUE"/"FALSE".
                var isDriver = "${DB_IS_DRIVER}" === "TRUE";
                event.Put("databricks.node_role", isDriver ? "Driver" : "Executor");
              }
        - add_fields:
            target: databricks
            fields:
              cluster_id: ${DB_CLUSTER_ID}
              container_ip: ${DB_CONTAINER_IP}
              instance_type: ${DB_INSTANCE_TYPE}
              cluster_name: ${DB_CLUSTER_NAME}
              is_job_cluster: ${DB_IS_JOB_CLUSTER}
      - metricsets:
        - filesystem
        data_stream.dataset: system.filesystem
        processors:
        - script:
            lang: javascript
            source: >
              function process(event) {
                // DB_IS_DRIVER is provided by Databricks as "TRUE"/"FALSE".
                var isDriver = "${DB_IS_DRIVER}" === "TRUE";
                event.Put("databricks.node_role", isDriver ? "Driver" : "Executor");
              }
        - add_fields:
            target: databricks
            fields:
              cluster_id: ${DB_CLUSTER_ID}
              container_ip: ${DB_CONTAINER_IP}
              instance_type: ${DB_INSTANCE_TYPE}
              cluster_name: ${DB_CLUSTER_NAME}
              is_job_cluster: ${DB_IS_JOB_CLUSTER}
      - metricsets:
        - process
        data_stream.dataset: system.process
        processors:
        - script:
            lang: javascript
            source: >
              function process(event) {
                // DB_IS_DRIVER is provided by Databricks as "TRUE"/"FALSE".
                var isDriver = "${DB_IS_DRIVER}" === "TRUE";
                event.Put("databricks.node_role", isDriver ? "Driver" : "Executor");
              }
        - add_fields:
            target: databricks
            fields:
              cluster_id: ${DB_CLUSTER_ID}
              container_ip: ${DB_CONTAINER_IP}
              instance_type: ${DB_INSTANCE_TYPE}
              cluster_name: ${DB_CLUSTER_NAME}
              is_job_cluster: ${DB_IS_JOB_CLUSTER}
      - metricsets:
        - process_summary
        data_stream.dataset: system.process_summary
        processors:
        - script:
            lang: javascript
            source: >
              function process(event) {
                // DB_IS_DRIVER is provided by Databricks as "TRUE"/"FALSE".
                var isDriver = "${DB_IS_DRIVER}" === "TRUE";
                event.Put("databricks.node_role", isDriver ? "Driver" : "Executor");
              }
        - add_fields:
            target: databricks
            fields:
              cluster_id: ${DB_CLUSTER_ID}
              container_ip: ${DB_CONTAINER_IP}
              instance_type: ${DB_INSTANCE_TYPE}
              cluster_name: ${DB_CLUSTER_NAME}
              is_job_cluster: ${DB_IS_JOB_CLUSTER}
      - metricsets:
        - socket
        data_stream.dataset: system.socket
        processors:
        - script:
            lang: javascript
            source: >
              function process(event) {
                // DB_IS_DRIVER is provided by Databricks as "TRUE"/"FALSE".
                var isDriver = "${DB_IS_DRIVER}" === "TRUE";
                event.Put("databricks.node_role", isDriver ? "Driver" : "Executor");
              }
        - add_fields:
            target: databricks
            fields:
              cluster_id: ${DB_CLUSTER_ID}
              container_ip: ${DB_CONTAINER_IP}
              instance_type: ${DB_INSTANCE_TYPE}
              cluster_name: ${DB_CLUSTER_NAME}
              is_job_cluster: ${DB_IS_JOB_CLUSTER}
      - metricsets:
        - socket_summary
        data_stream.dataset: system.socket_summary
        processors:
        - script:
            lang: javascript
            source: >
              function process(event) {
                // DB_IS_DRIVER is provided by Databricks as "TRUE"/"FALSE".
                var isDriver = "${DB_IS_DRIVER}" === "TRUE";
                event.Put("databricks.node_role", isDriver ? "Driver" : "Executor");
              }
        - add_fields:
            target: databricks
            fields:
              cluster_id: ${DB_CLUSTER_ID}
              container_ip: ${DB_CONTAINER_IP}
              instance_type: ${DB_INSTANCE_TYPE}
              cluster_name: ${DB_CLUSTER_NAME}
              is_job_cluster: ${DB_IS_JOB_CLUSTER}
      - metricsets:
        - diskio
        data_stream.dataset: system.diskio
        processors:
        - script:
            lang: javascript
            source: >
              function process(event) {
                // DB_IS_DRIVER is provided by Databricks as "TRUE"/"FALSE".
                var isDriver = "${DB_IS_DRIVER}" === "TRUE";
                event.Put("databricks.node_role", isDriver ? "Driver" : "Executor");
              }
        - add_fields:
            target: databricks
            fields:
              cluster_id: ${DB_CLUSTER_ID}
              container_ip: ${DB_CONTAINER_IP}
              instance_type: ${DB_INSTANCE_TYPE}
              cluster_name: ${DB_CLUSTER_NAME}
              is_job_cluster: ${DB_IS_JOB_CLUSTER}
      - metricsets:
        - load
        data_stream.dataset: system.load
        processors:
        - script:
            lang: javascript
            source: >
              function process(event) {
                // DB_IS_DRIVER is provided by Databricks as "TRUE"/"FALSE".
                var isDriver = "${DB_IS_DRIVER}" === "TRUE";
                event.Put("databricks.node_role", isDriver ? "Driver" : "Executor");
              }
        - add_fields:
            target: databricks
            fields:
              cluster_id: ${DB_CLUSTER_ID}
              container_ip: ${DB_CONTAINER_IP}
              instance_type: ${DB_INSTANCE_TYPE}
              cluster_name: ${DB_CLUSTER_NAME}
              is_job_cluster: ${DB_IS_JOB_CLUSTER}
      - metricsets:
        - uptime
        data_stream.dataset: system.uptime
        processors:
        - script:
            lang: javascript
            source: >
              function process(event) {
                // DB_IS_DRIVER is provided by Databricks as "TRUE"/"FALSE".
                var isDriver = "${DB_IS_DRIVER}" === "TRUE";
                event.Put("databricks.node_role", isDriver ? "Driver" : "Executor");
              }
        - add_fields:
            target: databricks
            fields:
              cluster_id: ${DB_CLUSTER_ID}
              container_ip: ${DB_CONTAINER_IP}
              instance_type: ${DB_INSTANCE_TYPE}
              cluster_name: ${DB_CLUSTER_NAME}
              is_job_cluster: ${DB_IS_JOB_CLUSTER}
      - metricsets:
        - fsstat
        data_stream.dataset: system.fsstat
        processors:
        - script:
            lang: javascript
            source: >
              function process(event) {
                // DB_IS_DRIVER is provided by Databricks as "TRUE"/"FALSE".
                var isDriver = "${DB_IS_DRIVER}" === "TRUE";
                event.Put("databricks.node_role", isDriver ? "Driver" : "Executor");
              }
        - add_fields:
            target: databricks
            fields:
              cluster_id: ${DB_CLUSTER_ID}
              container_ip: ${DB_CONTAINER_IP}
              instance_type: ${DB_INSTANCE_TYPE}
              cluster_name: ${DB_CLUSTER_NAME}
              is_job_cluster: ${DB_IS_JOB_CLUSTER}
  - data_stream:
      namespace: default
      name: apache-spark-1
    id: apache-spark-1
    streams:
      - data_stream:
          dataset: apache_spark.application
          type: metrics
        id: application-1
        hosts:
          - http://localhost:7777
        jmx:
          mappings:
            - attributes:
                - attr: Value
                  field: application.runtime.ms
              mbean: metrics:name=application.*.runtime_ms,type=gauges
            - attributes:
                - attr: Value
                  field: application.cores
              mbean: metrics:name=application.*.cores,type=gauges
            - attributes:
                - attr: Value
                  field: application.status
              mbean: metrics:name=application.*.status,type=gauges
        metricsets:
          - jmx
        namespace: metrics
        path: /jolokia/?ignoreErrors=true&canonicalNaming=false
        processors:
        - script:
            lang: javascript
            source: >
              function process(event) {
                // DB_IS_DRIVER is provided by Databricks as "TRUE"/"FALSE".
                var isDriver = "${DB_IS_DRIVER}" === "TRUE";
                event.Put("databricks.node_role", isDriver ? "Driver" : "Executor");
              }
        - add_fields:
            target: databricks
            fields:
              cluster_id: ${DB_CLUSTER_ID}
              container_ip: ${DB_CONTAINER_IP}
              instance_type: ${DB_INSTANCE_TYPE}
              cluster_name: ${DB_CLUSTER_NAME}
              is_job_cluster: ${DB_IS_JOB_CLUSTER}
        period: 60s
      - data_stream:
          dataset: apache_spark.node
          type: metrics
        id: node-1
        hosts:
          - http://localhost:7777
        jmx:
          mappings:
            - attributes:
                - attr: Value
                  field: node.main.applications.count
              mbean: metrics:name=master.apps,type=gauges
            - attributes:
                - attr: Value
                  field: node.main.applications.waiting
              mbean: metrics:name=master.waitingApps,type=gauges
            - attributes:
                - attr: Value
                  field: node.main.workers.alive
              mbean: metrics:name=master.aliveWorkers,type=gauges
            - attributes:
                - attr: Value
                  field: node.main.workers.count
              mbean: metrics:name=master.workers,type=gauges
            - attributes:
                - attr: Value
                  field: node.worker.executors
              mbean: metrics:name=worker.executors,type=gauges
            - attributes:
                - attr: Value
                  field: node.worker.cores.used
              mbean: metrics:name=worker.coresUsed,type=gauges
            - attributes:
                - attr: Value
                  field: node.worker.cores.free
              mbean: metrics:name=worker.coresFree,type=gauges
            - attributes:
                - attr: Value
                  field: node.worker.memory.used
              mbean: metrics:name=worker.memUsed_MB,type=gauges
            - attributes:
                - attr: Value
                  field: node.worker.memory.free
              mbean: metrics:name=worker.memFree_MB,type=gauges
        metricsets:
          - jmx
        namespace: metrics
        path: /jolokia/?ignoreErrors=true&canonicalNaming=false
        processors:
        - script:
            lang: javascript
            source: >
              function process(event) {
                // DB_IS_DRIVER is provided by Databricks as "TRUE"/"FALSE".
                var isDriver = "${DB_IS_DRIVER}" === "TRUE";
                event.Put("databricks.node_role", isDriver ? "Driver" : "Executor");
              }
        - add_fields:
            target: databricks
            fields:
              cluster_id: ${DB_CLUSTER_ID}
              container_ip: ${DB_CONTAINER_IP}
              instance_type: ${DB_INSTANCE_TYPE}
              cluster_name: ${DB_CLUSTER_NAME}
              is_job_cluster: ${DB_IS_JOB_CLUSTER}
        period: 60s
      - data_stream:
          dataset: apache_spark.executor
          type: metrics
        hosts:
          - http://localhost:7777
        id: executor-1
        jmx:
          mappings:
            - attributes:
                - attr: Count
                  field: executor.bytes.read
              mbean: metrics:name=*.*.executor.bytesRead,type=counters
            - attributes:
                - attr: Count
                  field: executor.bytes.written
              mbean: metrics:name=*.*.executor.bytesWritten,type=counters
            - attributes:
                - attr: Value
                  field: executor.memory.direct_pool
              mbean: metrics:name=*.*.ExecutorMetrics.DirectPoolMemory,type=gauges
            - attributes:
                - attr: Count
                  field: executor.disk_bytes_spilled
              mbean: metrics:name=*.*.executor.diskBytesSpilled,type=counters
            - attributes:
                - attr: Count
                  field: executor.file_cache_hits
              mbean: metrics:name=*.*.HiveExternalCatalog.fileCacheHits,type=counters
            - attributes:
                - attr: Count
                  field: executor.files_discovered
              mbean: metrics:name=*.*.HiveExternalCatalog.filesDiscovered,type=counters
            - attributes:
                - attr: Value
                  field: executor.filesystem.file.large_read_ops
              mbean: metrics:name=*.*.executor.filesystem.file.largeRead_ops,type=gauges
            - attributes:
                - attr: Value
                  field: executor.filesystem.file.read_bytes
              mbean: metrics:name=*.*.executor.filesystem.file.read_bytes,type=gauges
            - attributes:
                - attr: Value
                  field: executor.filesystem.file.read_ops
              mbean: metrics:name=*.*.executor.filesystem.file.read_ops,type=gauges
            - attributes:
                - attr: Value
                  field: executor.filesystem.file.write_bytes
              mbean: metrics:name=*.*.executor.filesystem.file.write_bytes,type=gauges
            - attributes:
                - attr: Value
                  field: executor.filesystem.file.write_ops
              mbean: metrics:name=*.*.executor.filesystem.file.write_ops,type=gauges
            - attributes:
                - attr: Value
                  field: executor.filesystem.hdfs.large_read_ops
              mbean: metrics:name=*.*.executor.filesystem.hdfs.largeRead_ops,type=gauges
            - attributes:
                - attr: Value
                  field: executor.filesystem.hdfs.read_bytes
              mbean: metrics:name=*.*.executor.filesystem.hdfs.read_bytes,type=gauges
            - attributes:
                - attr: Value
                  field: executor.filesystem.hdfs.read_ops
              mbean: metrics:name=*.*.executor.filesystem.hdfs.read_ops,type=gauges
            - attributes:
                - attr: Value
                  field: executor.filesystem.hdfs.write_bytes
              mbean: metrics:name=*.*.executor.filesystem.hdfs.write_bytes,type=gauges
            - attributes:
                - attr: Value
                  field: executor.filesystem.hdfs.write_ops
              mbean: metrics:name=*.*.executor.filesystem.hdfs.write_ops,type=gauges
            - attributes:
                - attr: Count
                  field: executor.hive_client_calls
              mbean: metrics:name=*.*.HiveExternalCatalog.hiveClientCalls,type=counters
            - attributes:
                - attr: Value
                  field: executor.jvm.cpu_time
              mbean: metrics:name=*.*.JVMCPU.jvmCpuTime,type=gauges
            - attributes:
                - attr: Count
                  field: executor.jvm.gc_time
              mbean: metrics:name=*.*.executor.jvmGCTime,type=counters
            - attributes:
                - attr: Value
                  field: executor.memory.jvm.heap
              mbean: metrics:name=*.*.ExecutorMetrics.JVMHeapMemory,type=gauges
            - attributes:
                - attr: Value
                  field: executor.memory.jvm.off_heap
              mbean: metrics:name=*.*.ExecutorMetrics.JVMOffHeapMemory,type=gauges
            - attributes:
                - attr: Value
                  field: executor.gc.major.count
              mbean: metrics:name=*.*.ExecutorMetrics.MajorGCCount,type=gauges
            - attributes:
                - attr: Value
                  field: executor.gc.major.time
              mbean: metrics:name=*.*.ExecutorMetrics.MajorGCTime,type=gauges
            - attributes:
                - attr: Value
                  field: executor.memory.mapped_pool
              mbean: metrics:name=*.*.ExecutorMetrics.MappedPoolMemory,type=gauges
            - attributes:
                - attr: Count
                  field: executor.memory_bytes_spilled
              mbean: metrics:name=*.*.executor.memoryBytesSpilled,type=counters
            - attributes:
                - attr: Value
                  field: executor.gc.minor.count
              mbean: metrics:name=*.*.ExecutorMetrics.MinorGCCount,type=gauges
            - attributes:
                - attr: Value
                  field: executor.gc.minor.time
              mbean: metrics:name=*.*.ExecutorMetrics.MinorGCTime,type=gauges
            - attributes:
                - attr: Value
                  field: executor.heap_memory.off.execution
              mbean: metrics:name=*.*.ExecutorMetrics.OffHeapExecutionMemory,type=gauges
            - attributes:
                - attr: Value
                  field: executor.heap_memory.off.storage
              mbean: metrics:name=*.*.ExecutorMetrics.OffHeapStorageMemory,type=gauges
            - attributes:
                - attr: Value
                  field: executor.heap_memory.off.unified
              mbean: metrics:name=*.*.ExecutorMetrics.OffHeapUnifiedMemory,type=gauges
            - attributes:
                - attr: Value
                  field: executor.heap_memory.on.execution
              mbean: metrics:name=*.*.ExecutorMetrics.OnHeapExecutionMemory,type=gauges
            - attributes:
                - attr: Value
                  field: executor.heap_memory.on.storage
              mbean: metrics:name=*.*.ExecutorMetrics.OnHeapStorageMemory,type=gauges
            - attributes:
                - attr: Value
                  field: executor.heap_memory.on.unified
              mbean: metrics:name=*.*.ExecutorMetrics.OnHeapUnifiedMemory,type=gauges
            - attributes:
                - attr: Count
                  field: executor.parallel_listing_job_count
              mbean: metrics:name=*.*.HiveExternalCatalog.parallelListingJobCount,type=counters
            - attributes:
                - attr: Count
                  field: executor.partitions_fetched
              mbean: metrics:name=*.*.HiveExternalCatalog.partitionsFetched,type=counters
            - attributes:
                - attr: Value
                  field: executor.process_tree.jvm.rss_memory
              mbean: metrics:name=*.*.ExecutorMetrics.ProcessTreeJVMRSSMemory,type=gauges
            - attributes:
                - attr: Value
                  field: executor.process_tree.jvm.v_memory
              mbean: metrics:name=*.*.ExecutorMetrics.ProcessTreeJVMVMemory,type=gauges
            - attributes:
                - attr: Value
                  field: executor.process_tree.other.rss_memory
              mbean: metrics:name=*.*.ExecutorMetrics.ProcessTreeOtherRSSMemory,type=gauges
            - attributes:
                - attr: Value
                  field: executor.process_tree.other.v_memory
              mbean: metrics:name=*.*.ExecutorMetrics.ProcessTreeOtherVMemory,type=gauges
            - attributes:
                - attr: Value
                  field: executor.process_tree.python.rss_memory
              mbean: metrics:name=*.*.ExecutorMetrics.ProcessTreePythonRSSMemory,type=gauges
            - attributes:
                - attr: Value
                  field: executor.process_tree.python.v_memory
              mbean: metrics:name=*.*.ExecutorMetrics.ProcessTreePythonVMemory,type=gauges
            - attributes:
                - attr: Count
                  field: executor.records.read
              mbean: metrics:name=*.*.executor.recordsRead,type=counters
            - attributes:
                - attr: Count
                  field: executor.records.written
              mbean: metrics:name=*.*.executor.recordsWritten,type=counters
            - attributes:
                - attr: Count
                  field: executor.result.serialization_time
              mbean: metrics:name=*.*.executor.resultSerializationTime,type=counters
            - attributes:
                - attr: Count
                  field: executor.result.size
              mbean: metrics:name=*.*.executor.resultSize,type=counters
            - attributes:
                - attr: Count
                  field: executor.run_time
              mbean: metrics:name=*.*.executor.runTime,type=counters
            - attributes:
                - attr: Value
                  field: executor.shuffle.client.used.direct_memory
              mbean: metrics:name=*.*.ExternalShuffle.shuffle-client.usedDirectMemory,type=gauges
            - attributes:
                - attr: Value
                  field: executor.shuffle.client.used.heap_memory
              mbean: metrics:name=*.*.ExternalShuffle.shuffle-client.usedHeapMemory,type=gauges
            - attributes:
                - attr: Count
                  field: executor.shuffle.bytes_written
              mbean: metrics:name=*.*.executor.shuffleBytesWritten,type=counters
            - attributes:
                - attr: Count
                  field: executor.shuffle.fetch_wait_time
              mbean: metrics:name=*.*.executor.shuffleFetchWaitTime,type=counters
            - attributes:
                - attr: Count
                  field: executor.shuffle.local.blocks_fetched
              mbean: metrics:name=*.*.executor.shuffleLocalBlocksFetched,type=counters
            - attributes:
                - attr: Count
                  field: executor.shuffle.local.bytes_read
              mbean: metrics:name=*.*.executor.shuffleLocalBytesRead,type=counters
            - attributes:
                - attr: Count
                  field: executor.shuffle.records.read
              mbean: metrics:name=*.*.executor.shuffleRecordsRead,type=counters
            - attributes:
                - attr: Count
                  field: executor.shuffle.records.written
              mbean: metrics:name=*.*.executor.shuffleRecordsWritten,type=counters
            - attributes:
                - attr: Count
                  field: executor.shuffle.remote.blocks_fetched
              mbean: metrics:name=*.*.executor.shuffleRemoteBlocksFetched,type=counters
            - attributes:
                - attr: Count
                  field: executor.shuffle.remote.bytes_read
              mbean: metrics:name=*.*.executor.shuffleRemoteBytesRead,type=counters
            - attributes:
                - attr: Count
                  field: executor.shuffle.remote.bytes_read_to_disk
              mbean: metrics:name=*.*.executor.shuffleRemoteBytesReadToDisk,type=counters
            - attributes:
                - attr: Count
                  field: executor.shuffle.total.bytes_read
              mbean: metrics:name=*.*.executor.shuffleTotalBytesRead,type=counters
            - attributes:
                - attr: Count
                  field: executor.shuffle.write.time
              mbean: metrics:name=*.*.executor.shuffleWriteTime,type=counters
            - attributes:
                - attr: Count
                  field: executor.succeeded_tasks
              mbean: metrics:name=*.*.executor.succeededTasks,type=counters
            - attributes:
                - attr: Value
                  field: executor.threadpool.active_tasks
              mbean: metrics:name=*.*.executor.threadpool.activeTasks,type=gauges
            - attributes:
                - attr: Value
                  field: executor.threadpool.complete_tasks
              mbean: metrics:name=*.*.executor.threadpool.completeTasks,type=gauges
            - attributes:
                - attr: Value
                  field: executor.threadpool.current_pool_size
              mbean: metrics:name=*.*.executor.threadpool.currentPool_size,type=gauges
            - attributes:
                - attr: Value
                  field: executor.threadpool.max_pool_size
              mbean: metrics:name=*.*.executor.threadpool.maxPool_size,type=gauges
            - attributes:
                - attr: Value
                  field: executor.threadpool.started_tasks
              mbean: metrics:name=*.*.executor.threadpool.startedTasks,type=gauges
        metricsets:
          - jmx
        namespace: metrics
        path: /jolokia/?ignoreErrors=true&canonicalNaming=false
        processors:
        - script:
            lang: javascript
            source: >
              function process(event) {
                // DB_IS_DRIVER is provided by Databricks as "TRUE"/"FALSE".
                var isDriver = "${DB_IS_DRIVER}" === "TRUE";
                event.Put("databricks.node_role", isDriver ? "Driver" : "Executor");
              }
        - add_fields:
            target: databricks
            fields:
              cluster_id: ${DB_CLUSTER_ID}
              container_ip: ${DB_CONTAINER_IP}
              instance_type: ${DB_INSTANCE_TYPE}
              cluster_name: ${DB_CLUSTER_NAME}
              is_job_cluster: ${DB_IS_JOB_CLUSTER}
        period: 60s
      - data_stream:
          dataset: apache_spark.driver
          type: metrics
        id: driver-1
        hosts:
          - http://localhost:7777
        jmx:
          mappings:
            - attributes:
                - attr: Value
                  field: driver.job_duration
              mbean: metrics:name=*.driver.appStatus.jobDuration,type=gauges
            - attributes:
                - attr: Count
                  field: driver.jobs.failed
              mbean: metrics:name=*.driver.appStatus.jobs.failedJobs,type=counters
            - attributes:
                - attr: Count
                  field: driver.jobs.succeeded
              mbean: metrics:name=*.driver.appStatus.jobs.succeededJobs,type=counters
            - attributes:
                - attr: Count
                  field: driver.stages.completed_count
              mbean: metrics:name=*.driver.appStatus.stages.completedStages,type=counters
            - attributes:
                - attr: Count
                  field: driver.stages.failed_count
              mbean: metrics:name=*.driver.appStatus.stages.failedStages,type=counters
            - attributes:
                - attr: Count
                  field: driver.stages.skipped_count
              mbean: metrics:name=*.driver.appStatus.stages.skippedStages,type=counters
            - attributes:
                - attr: Count
                  field: driver.tasks.executors.black_listed
              mbean: metrics:name=*.driver.appStatus.tasks.blackListedExecutors,type=counters
            - attributes:
                - attr: Count
                  field: driver.tasks.completed
              mbean: metrics:name=*.driver.appStatus.tasks.completedTasks,type=counters
            - attributes:
                - attr: Count
                  field: driver.tasks.executors.excluded
              mbean: metrics:name=*.driver.appStatus.tasks.excludedExecutors,type=counters
            - attributes:
                - attr: Count
                  field: driver.tasks.failed
              mbean: metrics:name=*.driver.appStatus.tasks.failedTasks,type=counters
            - attributes:
                - attr: Count
                  field: driver.tasks.killed
              mbean: metrics:name=*.driver.appStatus.tasks.killedTasks,type=counters
            - attributes:
                - attr: Count
                  field: driver.tasks.skipped
              mbean: metrics:name=*.driver.appStatus.tasks.skippedTasks,type=counters
            - attributes:
                - attr: Count
                  field: driver.tasks.executors.unblack_listed
              mbean: metrics:name=*.driver.appStatus.tasks.unblackListedExecutors,type=counters
            - attributes:
                - attr: Count
                  field: driver.tasks.executors.unexcluded
              mbean: metrics:name=*.driver.appStatus.tasks.unexcludedExecutors,type=counters
            - attributes:
                - attr: Value
                  field: driver.disk.space_used
              mbean: metrics:name=*.driver.BlockManager.disk.diskSpaceUsed_MB,type=gauges
            - attributes:
                - attr: Value
                  field: driver.memory.max_mem
              mbean: metrics:name=*.driver.BlockManager.memory.maxMem_MB,type=gauges
            - attributes:
                - attr: Value
                  field: driver.memory.off_heap.max
              mbean: metrics:name=*.driver.BlockManager.memory.maxOffHeapMem_MB,type=gauges
            - attributes:
                - attr: Value
                  field: driver.memory.on_heap.max
              mbean: metrics:name=*.driver.BlockManager.memory.maxOnHeapMem_MB,type=gauges
            - attributes:
                - attr: Value
                  field: driver.memory.used
              mbean: metrics:name=*.driver.BlockManager.memory.memUsed_MB,type=gauges
            - attributes:
                - attr: Value
                  field: driver.memory.off_heap.used
              mbean: metrics:name=*.driver.BlockManager.memory.offHeapMemUsed_MB,type=gauges
            - attributes:
                - attr: Value
                  field: driver.memory.on_heap.used
              mbean: metrics:name=*.driver.BlockManager.memory.onHeapMemUsed_MB,type=gauges
            - attributes:
                - attr: Value
                  field: driver.memory.remaining
              mbean: metrics:name=*.driver.BlockManager.memory.remainingMem_MB,type=gauges
            - attributes:
                - attr: Value
                  field: driver.memory.off_heap.remaining
              mbean: metrics:name=*.driver.BlockManager.memory.remainingOffHeapMem_MB,type=gauges
            - attributes:
                - attr: Value
                  field: driver.memory.on_heap.remaining
              mbean: metrics:name=*.driver.BlockManager.memory.remainingOnHeapMem_MB,type=gauges
            - attributes:
                - attr: Value
                  field: driver.dag_scheduler.job.active
              mbean: metrics:name=*.driver.DAGScheduler.job.activeJobs,type=gauges
            - attributes:
                - attr: Value
                  field: driver.dag_scheduler.job.all
              mbean: metrics:name=*.driver.DAGScheduler.job.allJobs,type=gauges
            - attributes:
                - attr: Value
                  field: driver.dag_scheduler.stages.failed
              mbean: metrics:name=*.driver.DAGScheduler.stage.failedStages,type=gauges
            - attributes:
                - attr: Value
                  field: driver.dag_scheduler.stages.running
              mbean: metrics:name=*.driver.DAGScheduler.stage.runningStages,type=gauges
            - attributes:
                - attr: Value
                  field: driver.dag_scheduler.stages.waiting
              mbean: metrics:name=*.driver.DAGScheduler.stage.waitingStages,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executors.all
              mbean: metrics:name=*.driver.ExecutorAllocationManager.executors.numberAllExecutors,type=gauges
            - attributes:
                - attr: Count
                  field: driver.executors.decommission_unfinished
              mbean: metrics:name=*.driver.ExecutorAllocationManager.executors.numberExecutorsDecommissionUnfinished,type=counters
            - attributes:
                - attr: Count
                  field: driver.executors.exited_unexpectedly
              mbean: metrics:name=*.driver.ExecutorAllocationManager.executors.numberExecutorsExitedUnexpectedly,type=counters
            - attributes:
                - attr: Count
                  field: driver.executors.gracefully_decommissioned
              mbean: metrics:name=*.driver.ExecutorAllocationManager.executors.numberExecutorsGracefullyDecommissioned,type=counters
            - attributes:
                - attr: Count
                  field: driver.executors.killed_by_driver
              mbean: metrics:name=*.driver.ExecutorAllocationManager.executors.numberExecutorsKilledByDriver,type=counters
            - attributes:
                - attr: Value
                  field: driver.executors.pending_to_remove
              mbean: metrics:name=*.driver.ExecutorAllocationManager.executors.numberExecutorsPendingToRemove,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executors.to_add
              mbean: metrics:name=*.driver.ExecutorAllocationManager.executors.numberExecutorsToAdd,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executors.max_needed
              mbean: metrics:name=*.driver.ExecutorAllocationManager.executors.numberMaxNeededExecutors,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executors.target
              mbean: metrics:name=*.driver.ExecutorAllocationManager.executors.numberTargetExecutors,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executor_metrics.memory.direct_pool
              mbean: metrics:name=*.driver.ExecutorMetrics.DirectPoolMemory,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executor_metrics.memory.jvm.heap
              mbean: metrics:name=*.driver.ExecutorMetrics.JVMHeapMemory,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executor_metrics.memory.jvm.off_heap
              mbean: metrics:name=*.driver.ExecutorMetrics.JVMOffHeapMemory,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executor_metrics.memory.mapped_pool
              mbean: metrics:name=*.driver.ExecutorMetrics.MappedPoolMemory,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executor_metrics.gc.major.count
              mbean: metrics:name=*.driver.ExecutorMetrics.MajorGCCount,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executor_metrics.gc.major.time
              mbean: metrics:name=*.driver.ExecutorMetrics.MajorGCTime,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executor_metrics.gc.minor.count
              mbean: metrics:name=*.driver.ExecutorMetrics.MinorGCCount,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executor_metrics.gc.minor.time
              mbean: metrics:name=*.driver.ExecutorMetrics.MinorGCTime,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executor_metrics.heap_memory.off.execution
              mbean: metrics:name=*.driver.ExecutorMetrics.OffHeapExecutionMemory,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executor_metrics.heap_memory.off.storage
              mbean: metrics:name=*.driver.ExecutorMetrics.OffHeapStorageMemory,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executor_metrics.heap_memory.off.unified
              mbean: metrics:name=*.driver.ExecutorMetrics.OffHeapUnifiedMemory,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executor_metrics.heap_memory.on.execution
              mbean: metrics:name=*.driver.ExecutorMetrics.OnHeapExecutionMemory,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executor_metrics.heap_memory.on.storage
              mbean: metrics:name=*.driver.ExecutorMetrics.OnHeapStorageMemory,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executor_metrics.heap_memory.on.unified
              mbean: metrics:name=*.driver.ExecutorMetrics.OnHeapUnifiedMemory,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executor_metrics.process_tree.jvm.rss_memory
              mbean: metrics:name=*.driver.ExecutorMetrics.ProcessTreeJVMRSSMemory,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executor_metrics.process_tree.jvm.v_memory
              mbean: metrics:name=*.driver.ExecutorMetrics.ProcessTreeJVMVMemory,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executor_metrics.process_tree.other.rss_memory
              mbean: metrics:name=*.driver.ExecutorMetrics.ProcessTreeOtherRSSMemory,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executor_metrics.process_tree.other.v_memory
              mbean: metrics:name=*.driver.ExecutorMetrics.ProcessTreeOtherVMemory,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executor_metrics.process_tree.python.rss_memory
              mbean: metrics:name=*.driver.ExecutorMetrics.ProcessTreePythonRSSMemory,type=gauges
            - attributes:
                - attr: Value
                  field: driver.executor_metrics.process_tree.python.v_memory
              mbean: metrics:name=*.driver.ExecutorMetrics.ProcessTreePythonVMemory,type=gauges
            - attributes:
                - attr: Count
                  field: driver.hive_external_catalog.file_cache_hits
              mbean: metrics:name=*.driver.HiveExternalCatalog.fileCacheHits,type=counters
            - attributes:
                - attr: Count
                  field: driver.hive_external_catalog.files_discovered
              mbean: metrics:name=*.driver.HiveExternalCatalog.filesDiscovered,type=counters
            - attributes:
                - attr: Count
                  field: driver.hive_external_catalog.hive_client_calls
              mbean: metrics:name=*.driver.HiveExternalCatalog.hiveClientCalls,type=counters
            - attributes:
                - attr: Count
                  field: driver.hive_external_catalog.parallel_listing_job.count
              mbean: metrics:name=*.driver.HiveExternalCatalog.parallelListingJobCount,type=counters
            - attributes:
                - attr: Count
                  field: driver.hive_external_catalog.partitions_fetched
              mbean: metrics:name=*.driver.HiveExternalCatalog.partitionsFetched,type=counters
            - attributes:
                - attr: Value
                  field: driver.jvm.cpu.time
              mbean: metrics:name=*.driver.JVMCPU.jvmCpuTime,type=gauges
            - attributes:
                - attr: Value
                  field: driver.spark.streaming.states.rows.total
              mbean: metrics:name=*.driver.spark.streaming.*.states-rowsTotal,type=gauges
            - attributes:
                - attr: Value
                  field: driver.spark.streaming.processing_rate.total
              mbean: metrics:name=*.driver.spark.streaming.*.processingRate-total,type=gauges
            - attributes:
                - attr: Value
                  field: driver.spark.streaming.latency
              mbean: metrics:name=*.driver.spark.streaming.*.latency,type=gauges
            - attributes:
                - attr: Value
                  field: driver.spark.streaming.states.used_bytes
              mbean: metrics:name=*.driver.spark.streaming.*.states-usedBytes,type=gauges
            - attributes:
                - attr: Value
                  field: driver.spark.streaming.event_time.watermark
              mbean: metrics:name=*.driver.spark.streaming.*.eventTime-watermark,type=gauges
            - attributes:
                - attr: Value
                  field: driver.spark.streaming.input_rate.total
              mbean: metrics:name=*.driver.spark.streaming.*.inputRate-total,type=gauges
        metricsets:
          - jmx
        namespace: metrics
        path: /jolokia/?ignoreErrors=true&canonicalNaming=false
        processors:
        - script:
            lang: javascript
            source: >
              function process(event) {
                // DB_IS_DRIVER is provided by Databricks as "TRUE"/"FALSE".
                var isDriver = "${DB_IS_DRIVER}" === "TRUE";
                event.Put("databricks.node_role", isDriver ? "Driver" : "Executor");
              }
        - add_fields:
            target: databricks
            fields:
              cluster_id: ${DB_CLUSTER_ID}
              container_ip: ${DB_CONTAINER_IP}
              instance_type: ${DB_INSTANCE_TYPE}
              cluster_name: ${DB_CLUSTER_NAME}
              is_job_cluster: ${DB_IS_JOB_CLUSTER}
        period: 60s
    type: jolokia/metrics
    use_output: default
EOF

# ------- INSTALL STANDALONE AGENT -------
sudo ./elastic-agent install --non-interactive --config /tmp/elastic-agent-${ELASTIC_AGENT_VERSION}-${ARCH}/elastic-agent.yml

echo "Elastic Agent installed and configured for Apache Spark with Jolokia on port 7777."