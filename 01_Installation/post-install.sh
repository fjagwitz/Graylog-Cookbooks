#!/bin/bash
GL_GRAYLOG=$1
GL_GRAYLOG_MONITORING_STREAM=$2

environmentfile=$3
source $environmentfile

echo "[INFO] - STARTING POST-INSTALLATION STEPS "

## Pass Info about Monitoring Stream without using /etc/environment
## Use API Token instead of basic authentication

GL_GRAYLOG_ADMIN=$(cat $GL_GRAYLOG_INSTALLPATH/your_graylog_credentials.txt | awk -F'"' '{print $2}')
GL_GRAYLOG_PASSWORD=$(cat $GL_GRAYLOG_INSTALLPATH/your_graylog_credentials.txt | awk -F'"' '{print $4}')

# Graylog licenses
GL_GRAYLOG_LICENSE_ENTERPRISE=""
GL_GRAYLOG_LICENSE_SECURITY=""

#
## Configuring Enterprise Features
#

while [[ ${GL_GRAYLOG_LICENSE_ENTERPRISE} != "true" ]]
do 
  echo "[INFO] - WAITING FOR GRAYLOG ENTERPRISE LICENSE TO BE PROVISIONED "
  GL_GRAYLOG_LICENSE_ENTERPRISE=$(curl -H 'Cache-Control: no-cache, no-store' -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" | jq .[] | jq '.[] | select(.active == true and .license.subject == "/license/enterprise")' | jq -r .active )
  sleep 5s
done

sleep 1m

echo "[INFO] - STOPPING GRAYLOG STACK "

sudo docker compose -f ${GL_GRAYLOG}/docker-compose.yaml down 2>/dev/null >/dev/null

echo "[INFO] - STARTING GRAYLOG STACK "

sudo docker compose -f ${GL_GRAYLOG}/docker-compose.yaml up -d 2>/dev/null >/dev/null

while [[ $(curl -s http://localhost/api/system/lbstatus) != "ALIVE" ]]
do
  echo "[INFO] - WAIT FOR THE SYSTEM TO COME UP "
  sleep 5s
done

if [[ ${GL_GRAYLOG_LICENSE_ENTERPRISE} == "true" ]]
then
  # Adding Graylog Forwarder Input
  # 
  echo "[INFO] - CREATE GRAYLOG FORWARDER INPUT "
  curl -s http://localhost/api/system/inputs -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{"type":"org.graylog.plugins.forwarder.input.ForwarderServiceInput","configuration":{"forwarder_bind_address":"0.0.0.0","forwarder_message_transmission_port":13301,"forwarder_configuration_port":13302,"forwarder_grpc_enable_tls":false,"forwarder_grpc_tls_trust_chain_cert_file":"","forwarder_grpc_tls_private_key_file":"","forwarder_grpc_tls_private_key_file_password":""},"title":"Graylog Enterprise Forwarder | Evaluation Input","global":true}' 2>/dev/null >/dev/null

  # Adding Header Badge
  #
  echo "[INFO] - ENABLE HEADER BADGE "
  enabled_header_badge=$(curl -s http://localhost/api/system/cluster_config/org.graylog.plugins.customization.HeaderBadge -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X GET -H "X-Requested-By: localhost" | jq .badge_enable)

  if [[ $enabled_header_badge != "true" ]]
  then
    curl -s http://localhost/api/system/cluster_config/org.graylog.plugins.customization.HeaderBadge -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"badge_enable": true,"badge_color": "#689f38","badge_text": "EVAL"}' 2>/dev/null >/dev/null
  else
      echo "[INFO] - NO HEADER BADGE ADDED, KEPT EXISTING ONE "
  fi

  # Adding Warning Message to avoid Production Use
  #
  echo "[INFO] - CREATE WARNING MESSAGE "
  warning_message=$(curl -s http://localhost/api/plugins/org.graylog.plugins.customization/notifications -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X GET -H "X-Requested-By: localhost" | jq .[].isActive) 2>/dev/null >/dev/null

  if [[ $warning_message != "true" ]] 
  then
    curl -s http://localhost/api/plugins/org.graylog.plugins.customization/notifications -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"title":"Evaluation System","shortMessage":"DO NOT USE IN PRODUCTION","longMessage":"This System was set up for a Graylog Product Evaluation and MUST NOT be used in production. For a secure and production-ready setup please get in touch with your Graylog Customer Success Manager who will help you to deploy your Graylog Stack following best practices.","isActive":true,"isDismissible":true,"atLogin":true,"isGlobal":false,"variant":"warning","hiddenTitle":false}' 2>/dev/null >/dev/null
  else
    echo "[INFO] - NO HEADER BADGE ADDED, KEPT EXISTING ONE " 
  fi

  # Changing Colour Scheme to Graylog 5
  #
  # echo "[INFO] - CHANGE COLOUR SCHEME TO v5 "
  # curl -s http://localhost/api/plugins/org.graylog.plugins.customization/theme -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"light":{"global":{"background":"#eeeff2","link":"#578dcc"},"brand":{"tertiary":"#3e434c"},"variant":{"default":"#9aa8bd","danger":"#eb5454","info":"#578dcc","primary":"#697586","success":"#7eb356","warning":"#eedf64"}},"dark":{"global":{"background":"#222222","contentBackground":"#303030","link":"#629de2"},"brand":{"tertiary":"#ffffff"},"variant":{"default":"#595959","danger":"#e74c3c","info":"#578dcc","primary":"#697586","success":"#709e4c","warning":"#e3d45f"}}}' 2>/dev/null >/dev/null

  echo "[INFO] - CONFIGURE ARCHIVE "
  backend=$(curl -s http://localhost/api/plugins/org.graylog.plugins.archive/config -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X GET -H "X-Requested-By: localhost" -H 'Content-Type: application/json' | jq -r .backend_id)

  curl -s http://localhost/api/plugins/org.graylog.plugins.archive/config -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"archive_path\": \"/usr/share/graylog/data/archives\",\"max_segment_size\": 524288000,\"segment_filename_prefix\": \"archive-segment\",\"segment_compression_type\": \"GZIP\",\"metadata_filename\": \"archive-metadata.json\",\"histogram_bucket_size\": 86400000,\"restore_index_batch_size\": 1000,\"excluded_streams\": [],\"segment_checksum_type\": \"CRC32\",\"backend_id\": \"$backend\",\"archive_failure_threshold\": 1,\"retention_time\": 30,\"restrict_to_leader\": true,\"parallelize_archive_creation\": true}" 2>/dev/null >/dev/null

  # Enabling Warm Tier 
  #
  echo "[INFO] - ENABLE WARM TIER "
  warm_tier_name=$(curl -s http://localhost/api/plugins/org.graylog.plugins.datatiering/datatiering/repositories -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"type":"fs","name":"warm_tier","location":"/usr/share/opensearch/warm_tier"}' | jq -r .name) 2>/dev/null >/dev/null

  # Creating Index Set Template for Evaluation Purposes
  #
  echo "[INFO] - CREATE EVALUATION INDEX SET TEMPLATE "
  index_set_template=$(curl -s http://localhost/api/system/indices/index_sets/templates -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"title\": \"Evaluation Storage\",\"description\": \"Use case: Graylog Product Evaluation\",\"index_set_config\": {\"shards\": 1,\"replicas\": 0,\"index_optimization_max_num_segments\": 1,\"index_optimization_disabled\": false,\"field_type_refresh_interval\": 5000,\"data_tiering\": {\"type\": \"hot_warm\",\"index_lifetime_min\": \"P7D\",\"index_lifetime_max\": \"P10D\",\"warm_tier_enabled\": true,\"index_hot_lifetime_min\": \"P3D\",\"warm_tier_repository_name\": \"$warm_tier_name\",\"archive_before_deletion\": true},\"index_analyzer\": \"standard\",\"use_legacy_rotation\": false}}" | jq -r .id) 

  echo "[INFO] - CONFIGURE EVALUATION INDEX SET TEMPLATE AS DEFAULT"
  curl -s http://localhost/api/system/indices/index_set_defaults -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"id\":\"$index_set_template\"}" 2>/dev/null >/dev/null

  # Creating Data Lake Backend
  #
  echo "[INFO] - CREATE DATALAKE "

  active_backend=$(curl -s http://localhost/api/plugins/org.graylog.plugins.datalake/data_lake/backends -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"title":"File System Data Lake","description":"Data Lake on the local Filesystem","settings":{"type":"fs-1","output_path":"/usr/share/graylog/data/datalake","usage_threshold":80}}' | jq -r .id) 2>/dev/null >/dev/null

  echo "[INFO] - ENABLE DATALAKE "
  curl -s http://localhost/api/plugins/org.graylog.plugins.datalake/data_lake/config -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"active_backend\":\"$active_backend\",\"iceberg_commit_interval\":\"PT15M\",\"iceberg_target_file_size\":536870912,\"parquet_row_group_size\":134217728,\"parquet_page_size\":8192,\"journal_reader_batch_size\":500,\"optimize_job_enabled\":true,\"optimize_job_interval\":\"PT1H\",\"optimize_max_concurrent_file_rewrites\":null,\"parallel_retrieval_enabled\":true,\"retrieval_convert_threads\":-1,\"retrieval_convert_batch_size\":1,\"retrieval_inflight_requests\":3,\"retrieval_bulk_batch_size\":2500,\"retention_time\":null}" 2>/dev/null >/dev/null

  echo "[INFO] - CONFIGURE DATALAKE MAX RETENTION OF 7 DAYS "
  curl -s http://localhost/api/plugins/org.graylog.plugins.datalake/data_lake/config -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"active_backend\":\"$active_backend\",\"iceberg_commit_interval\":\"PT15M\",\"iceberg_target_file_size\":536870912,\"parquet_row_group_size\":134217728,\"parquet_page_size\":8192,\"journal_reader_batch_size\":500,\"optimize_job_enabled\":true,\"optimize_job_interval\":\"PT1H\",\"optimize_max_concurrent_file_rewrites\":null,\"parallel_retrieval_enabled\":true,\"retrieval_convert_threads\":-1,\"retrieval_convert_batch_size\":1,\"retrieval_inflight_requests\":3,\"retrieval_bulk_batch_size\":2500,\"retention_time\":\"P7D\"}" 2>/dev/null >/dev/null
  
  echo "[INFO] - CONFIGURE DATALAKE FOR SELF-MONITORING STREAM"
  curl -s http://localhost/api/plugins/org.graylog.plugins.datalake/data_lake/stream/config/enable -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"stream_ids\":[\"${GL_GRAYLOG_MONITORING_STREAM}\"],\"enabled\":true}" 2>/dev/null >/dev/null


  # Activate Illuminate for Linux Auditbeat
  #
  echo "[INFO] - INSTALL ILLUMINATE PACKAGES FOR AUDITBEAT "

  curl -s http://localhost/api/plugins/org.graylog.plugins.illuminate/bundles/latest/enable_packs -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"entity":{"processing_pack_ids":["illuminate-linux-auditbeat"],"spotlight_pack_ids":["61d75c3e-3551-4b97-bbb5-ea8181472cb0"]}}' 2>/dev/null >/dev/null

  # Installing Graylog Sidecar
  echo "[INFO] - INSTALL GRAYLOG SIDECAR "

  sudo wget https://packages.graylog2.org/repo/packages/graylog-sidecar-repository_1-5_all.deb 2>/dev/null >/dev/null
  sudo dpkg -i graylog-sidecar-repository_1-5_all.deb 2>/dev/null >/dev/null
  sudo apt-get update 2>/dev/null >/dev/null
  sudo apt-get install graylog-sidecar 2>/dev/null >/dev/null
  sudo rm graylog-sidecar-repository_1-5_all.deb 2>/dev/null >/dev/null

  # Creating Sidecar Token for Graylog Host
  SIDECAR_ID=$(curl -s http://localhost/api/users -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X GET -H "X-Requested-By: localhost" | jq .[] | jq '.[] | select(.username=="graylog-sidecar")' | jq -r .id)

  SIDECAR_TOKEN=$(curl -s http://localhost/api/users/${SIDECAR_ID}/tokens/EVALUATION-LOCAL-SIDECAR -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{"token_ttl":"P31D"}' | jq -r .token)

  # Configuring Graylog Sidecar for Graylog Host
  SIDECAR_YAML="/etc/graylog/sidecar/sidecar.yml"
  sudo cp ${SIDECAR_YAML} ${SIDECAR_YAML}.bak
  sudo sed -i "s\server_api_token: \"\"\server_api_token: \"${SIDECAR_TOKEN}\"\g" ${SIDECAR_YAML}
  sudo sed -i "s\#server_url: \"http://127.0.0.1:9000/api/\"\server_url: \"http://localhost/api/\"\g" ${SIDECAR_YAML}

  # Starting the Sidecar Service
  echo "[INFO] - START GRAYLOG SIDECAR "

  sudo graylog-sidecar -service install 2>/dev/null >/dev/null
  sudo systemctl enable graylog-sidecar 2>/dev/null >/dev/null
  sudo systemctl start graylog-sidecar 2>/dev/null >/dev/null

  # Cleanup /etc/environment
  # 
  # grep -vwE "(GL_GRAYLOG_MONITORING_STREAM)" $environmentfile | sudo tee $environmentfile 2>/dev/null >/dev/null
fi

#
## Configuring Security Features
#

while [[ $GL_GRAYLOG_LICENSE_SECURITY != "true" ]]
do 
  echo "[INFO] - WAITING FOR GRAYLOG SECURITY LICENSE TO BE PROVISIONED "
  GL_GRAYLOG_LICENSE_SECURITY=$(curl -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status?only_legacy=false -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" | jq .[] | jq '.[] | select(.active == true and .license.subject == "/license/enterprise")' | jq -r .active )
  sleep 5s
done

if [[ $GL_GRAYLOG_LICENSE_SECURITY == "true" ]]
then
  # Disabling Investigation AI Reports
  #
  active_ai_report=$(curl -s http://localhost/api/plugins/org.graylog.plugins.securityapp.investigations/ai/config -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X GET -H "X-Requested-By: localhost" | jq .investigations_ai_reports_enabled) 2>/dev/null >/dev/null

  if [[ $active_ai_report == "true" ]] || [[ $active_ai_report == "" ]]
  then 
    echo "[INFO] - DISABLE INVESTIGATION AI REPORTS "
    curl -s http://localhost/api/plugins/org.graylog.plugins.securityapp.investigations/ai/config/investigations_ai_reports_enabled -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X DELETE -H "X-Requested-By: localhost)" 2>/dev/null >/dev/null
  fi

fi 

exit 0
