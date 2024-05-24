# Adding Inputs to make sure Ports map to Nginx configuration
# Beats Input for Winlogbeat, Auditbeat, Filebeat
curl http://$(hostname)/api/system/inputs \
  -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" \
  -X POST \
  -H 'X-Requested-By: $(hostname)' \
  -H 'Content-Type: application/json' \
  -d '{ 
        "global": true,
        "title": "Port 5044 Beats | Evaluation Input",
        "type": "org.graylog.plugins.beats.Beats2Input",
        "configuration":
        {
          "recv_buffer_size": 262144,
          "port": 5044,
          "number_worker_threads": 4,
          "charset_name": "UTF-8",
          "bind_address": "0.0.0.0"
        }
      }' 
# Syslog UDP Input for Network Devices
curl http://$(hostname)/api/system/inputs \
  -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" \
  -X POST \
  -H 'X-Requested-By: $(hostname)' \
  -H 'Content-Type: application/json' \
  -d '{ 
        "global": true,
        "title": "Port 514 UDP Syslog | Evaluation Input",
        "type": "org.graylog2.inputs.syslog.udp.SyslogUDPInput",
        "configuration":
        {
          "recv_buffer_size": 262144,
          "port": 514,
          "number_worker_threads": 4,
          "charset_name": "UTF-8",
          "bind_address": "0.0.0.0"
        }
      }' 

# Syslog TCP Input for Network Devices
curl http://$(hostname)/api/system/inputs \
  -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" \
  -X POST \
  -H 'X-Requested-By: $(hostname)' \
  -H 'Content-Type: application/json' \
  -d '{ 
        "global": true,
        "title": "Port 514 TCP Syslog | Evaluation Input",
        "type": "org.graylog2.inputs.syslog.tcp.SyslogTCPInput",
        "configuration":
        {
          "recv_buffer_size": 262144,
          "port": 514,
          "number_worker_threads": 4,
          "charset_name": "UTF-8",
          "bind_address": "0.0.0.0"
        }
      }' 