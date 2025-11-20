

if [[ ${GL_GRAYLOG_LICENSE_ENTERPRISE} == "true" ]]
then
  # Adding Graylog Forwarder Input
  # 
  
  # Adding Header Badge
  #
 

  # Adding Warning Message to avoid Production Use
  #
  # Changing Colour Scheme to Graylog 5
  #
  



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
