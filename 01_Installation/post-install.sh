#!/bin/bash
environmentfile="/etc/environment"
source $environmentfile

GL_GRAYLOG_ADMIN=$(cat $GL_GRAYLOG_INSTALLPATH/your_graylog_credentials.txt | awk -F'"' '{print $2}')
GL_GRAYLOG_PASSWORD=$(cat $GL_GRAYLOG_INSTALLPATH/your_graylog_credentials.txt | awk -F'"' '{print $4}')

# Checking whether or not the system is getting a license
#
while [ $(curl -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status?only_legacy=false -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" | jq .status | jq length) -eq 0 ]
do
  echo "[INFO] - WAIT FOR THE SYSTEM TO BE LICENSED "
  active_license=$(curl -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status?only_legacy=false -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" | jq .status | jq length)
  sleep 5s
done

sleep 900s

if [ $(curl -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status?only_legacy=false -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" | jq .status | jq length) -gt 0 ]
then 
  # Adding Graylog Forwarder Input
  # 
  if [ $(curl -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status?only_legacy=false -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" | jq .status | jq length) -gt 0 ]
  then
  echo "[INFO] - CREATE GRAYLOG FORWARDER INPUT "
    curl -s http://localhost/api/system/inputs -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{"type":"org.graylog.plugins.forwarder.input.ForwarderServiceInput","configuration":{"forwarder_bind_address":"0.0.0.0","forwarder_message_transmission_port":13301,"forwarder_configuration_port":13302,"forwarder_grpc_enable_tls":false,"forwarder_grpc_tls_trust_chain_cert_file":"","forwarder_grpc_tls_private_key_file":"","forwarder_grpc_tls_private_key_file_password":""},"title":"Graylog Enterprise Forwarder | Evaluation Input","global":true}' 2>/dev/null >/dev/null
  fi

  # Adding Header Badge
  #
  if [ $(curl -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status?only_legacy=false -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" | jq .status | jq length) -gt 0 ]
  then
    echo "[INFO] - ENABLE HEADER BADGE "
    enabled_header_badge=$(curl -s http://localhost/api/system/cluster_config/org.graylog.plugins.customization.HeaderBadge -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X GET -H "X-Requested-By: localhost" | jq .badge_enable 2>/dev/null >/dev/null)
  fi

  if [ $(curl -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status?only_legacy=false -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" | jq .status | jq length) -gt 0 ] && ([[ $enabled_header_badge != "true" ]] || [[ $enabled_header_badge != "" ]])
  then
    curl -s http://localhost/api/system/cluster_config/org.graylog.plugins.customization.HeaderBadge -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"badge_enable": true,"badge_color": "#689f38","badge_text": "EVAL"}' 2>/dev/null >/dev/null
  fi

  # Adding Warning Message to avoid Production Use
  #
  if [ $(curl -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status?only_legacy=false -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" | jq .status | jq length) -gt 0 ]
  then
    echo "[INFO] - CREATE WARNING "
    warning_message=$(curl -s http://localhost/api/plugins/org.graylog.plugins.customization/notifications -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X GET -H "X-Requested-By: localhost") 2>/dev/null >/dev/null
  fi

  if [ $(curl -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status?only_legacy=false -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" | jq .status | jq length) -gt 0 ] && ([[ $warning_message == "{}" ]] || [[ $warning_message == "" ]])
  then
    curl -s http://localhost/api/plugins/org.graylog.plugins.customization/notifications -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"title":"Evaluation System","shortMessage":"DO NOT USE IN PRODUCTION","longMessage":"This System was set up for a Graylog Product Evaluation. For a secure and production-ready setup please get in touch with your Graylog Customer Success Manager who will help you to deploy your Graylog Stack following best practices. ","isActive":true,"isDismissible":true,"atLogin":true,"isGlobal":false,"variant":"warning","hiddenTitle":false}' 2>/dev/null >/dev/null
  fi

  # Changing Colour Scheme to Graylog 5
  #
  # if [ $(curl -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status?only_legacy=false -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" | jq .status | jq length) -gt 0 ] 
  # then
  #   echo "[INFO] - CHANGE COLOUR SCHEME TO v5 "
  #   curl -s http://localhost/api/plugins/org.graylog.plugins.customization/theme -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"light":{"global":{"background":"#eeeff2","link":"#578dcc"},"brand":{"tertiary":"#3e434c"},"variant":{"default":"#9aa8bd","danger":"#eb5454","info":"#578dcc","primary":"#697586","success":"#7eb356","warning":"#eedf64"}},"dark":{"global":{"background":"#222222","contentBackground":"#303030","link":"#629de2"},"brand":{"tertiary":"#ffffff"},"variant":{"default":"#595959","danger":"#e74c3c","info":"#578dcc","primary":"#697586","success":"#709e4c","warning":"#e3d45f"}}}' 2>/dev/null >/dev/null
  # fi

  if [ $(curl -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status?only_legacy=false -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" | jq .status | jq length) -gt 0 ] 
  then
    echo "[INFO] - CONFIGURE ARCHIVE "
    backend=$(curl -s http://localhost/api/plugins/org.graylog.plugins.archive/config -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X GET -H "X-Requested-By: localhost" -H 'Content-Type: application/json' | jq -r .backend_id)

    curl -s http://localhost/api/plugins/org.graylog.plugins.archive/config -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"archive_path\": \"/usr/share/graylog/data/archives\",\"max_segment_size\": 524288000,\"segment_filename_prefix\": \"archive-segment\",\"segment_compression_type\": \"GZIP\",\"metadata_filename\": \"archive-metadata.json\",\"histogram_bucket_size\": 86400000,\"restore_index_batch_size\": 1000,\"excluded_streams\": [],\"segment_checksum_type\": \"CRC32\",\"backend_id\": \"$backend\",\"archive_failure_threshold\": 1,\"retention_time\": 30,\"restrict_to_leader\": true,\"parallelize_archive_creation\": true}" 2>/dev/null >/dev/null
  fi

  # Enabling Warm Tier 
  #
  if [ $(curl -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status?only_legacy=false -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" | jq .status | jq length) -gt 0 ] 
  then
    echo "[INFO] - ENABLE WARM TIER "
    curl -s http://localhost/api/plugins/org.graylog.plugins.datatiering/datatiering/repositories -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"type":"fs","name":"warm_tier","location":"/usr/share/opensearch/warm_tier"}' 2>/dev/null >/dev/null
  fi

  # Creating Index Set Template for Evaluation Purposes
  #
  if [ $(curl -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status?only_legacy=false -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" | jq .status | jq length) -gt 0 ] 
  then
    echo "[INFO] - CREATE EVALUATION INDEX SET TEMPLATE "
    index_set_template=$(curl -s http://localhost/api/system/indices/index_sets/templates -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"title": "Evaluation Storage","description": "Use case: Graylog Product Evaluation","index_set_config": {"shards": 1,"replicas": 0,"index_optimization_max_num_segments": 1,"index_optimization_disabled": false,"field_type_refresh_interval": 5000,"data_tiering": {"type": "hot_warm","index_lifetime_min": "P7D","index_lifetime_max": "P10D","warm_tier_enabled": true,"index_hot_lifetime_min": "P3D","warm_tier_repository_name": "warm_tier","archive_before_deletion": true},"index_analyzer": "standard","use_legacy_rotation": false}}' | jq -r .id) 2>/dev/null >/dev/null

    echo "[INFO] - CONFIGURE EVALUATION INDEX SET TEMPLATE AS DEFAULT"
    curl -s http://localhost/api/system/indices/index_set_defaults -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"id\":\"$index_set_template\"}"
  fi

  # Creating Data Lake Backend
  #
  if [ $(curl -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status?only_legacy=false -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" | jq .status | jq length) -gt 0 ] 
  then
    echo "[INFO] - CREATE DATALAKE "
    active_backend=$(curl -s http://localhost/api/plugins/org.graylog.plugins.datawarehouse/data_warehouse/backends -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"title":"Data Lake","description":"Data Lake","settings":{"type":"fs-1","output_path":"/usr/share/graylog/data/datalake","usage_threshold":15}}' | jq -r .id) 2>/dev/null >/dev/null

    echo "[INFO] - ENABLE DATALAKE "
    curl -s http://localhost/api/plugins/org.graylog.plugins.datawarehouse/data_warehouse/config -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"active_backend\":\"$active_backend\",\"iceberg_commit_interval\":\"PT15M\",\"iceberg_target_file_size\":536870912,\"parquet_row_group_size\":134217728,\"parquet_page_size\":8192,\"journal_reader_batch_size\":500,\"optimize_job_enabled\":true,\"optimize_job_interval\":\"PT1H\",\"optimize_max_concurrent_file_rewrites\":null,\"parallel_retrieval_enabled\":true,\"retrieval_convert_threads\":-1,\"retrieval_convert_batch_size\":1,\"retrieval_inflight_requests\":3,\"retrieval_bulk_batch_size\":2500,\"retention_time\":null}" 2>/dev/null >/dev/null

    echo "[INFO] - CONFIGURE DATALAKE MAX RETENTION OF 7 DAYS "
    curl -s http://localhost/api/plugins/org.graylog.plugins.datawarehouse/data_warehouse/config -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"active_backend\":\"$active_backend\",\"iceberg_commit_interval\":\"PT15M\",\"iceberg_target_file_size\":536870912,\"parquet_row_group_size\":134217728,\"parquet_page_size\":8192,\"journal_reader_batch_size\":500,\"optimize_job_enabled\":true,\"optimize_job_interval\":\"PT1H\",\"optimize_max_concurrent_file_rewrites\":null,\"parallel_retrieval_enabled\":true,\"retrieval_convert_threads\":-1,\"retrieval_convert_batch_size\":1,\"retrieval_inflight_requests\":3,\"retrieval_bulk_batch_size\":2500,\"retention_time\":\"P7D\"}" 2>/dev/null >/dev/null
  fi

  while [ $(curl -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status?only_legacy=false -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" | jq .status | jq length) -eq 1 ]
  do
    echo "[INFO] - WAIT FOR THE SYSTEM TO BE LICENSED WITH A SECURITY LICENSE"
    active_license=$(curl -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status?only_legacy=false -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" | jq .status | jq length)
    sleep 5s
  done

  # Disabling Investigation AI Reports
  #
  if [ $(curl -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status?only_legacy=false -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" | jq .status | jq length) -gt 1 ]
  then
    active_ai_report=$(curl -s http://localhost/api/plugins/org.graylog.plugins.securityapp.investigations/ai/config -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X GET -H "X-Requested-By: localhost" | jq .investigations_ai_reports_enabled) 2>/dev/null >/dev/null
  fi 

  if [[ $active_ai_report == "true" ]] || [[ $active_ai_report == "" ]]
  then 
    echo "[INFO] - DISABLE INVESTIGATION AI REPORTS "
    curl -s http://localhost/api/plugins/org.graylog.plugins.securityapp.investigations/ai/config/investigations_ai_reports_enabled -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X DELETE -H "X-Requested-By: localhost)" 2>/dev/null >/dev/null
  fi

fi 

exit 0
