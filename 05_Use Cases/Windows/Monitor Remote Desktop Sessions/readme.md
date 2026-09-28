# Professionals: Remote Desktop Session Monitoring

## Requirements

- Graylog 7.1.9 or higher
- Graylog Enterprise or Security License
- Illuminate Content Pack "Microsoft Windows Security (2026.4.27)"

## How to install

- Upload and [Install](https://graylog.org/videos/content-packs/) the Content Pack in Graylog (the video is for Graylog v3.0 but it does still work the same way)
- Go to _"SYSTEM" / "CONTENT PACKS"_, filter for "pro" and klick on "Install":
  
  ![1](./images/1.png)
- Go to _"SYSTEM" / "PIPELINES"_, filter for "pro" and klick on "Edit":

  ![2](./images/2.png)
- Go to _"STREAMS" / "PIPELINES"_, filter for "pro" and klick on "Edit":
  
  ![3](./images/3.png)
- Choose "Illuminate: Windows Security Event Log Messages" and "Update connections":

  ![4](./images/4.png)
- Validate your settings and ensure the UI shows "This pipeline is processing messages from the stream "Illuminate:Windows Security Event Log Messages":
  
  ![5](./images/5.png)
- Go to _"DASHBOARDS"_, filter for "pro" and choose __"Graylog Professionals: Windows - RDP Monitoring"__:

  ![6](./images/6.png)
- Review your Dashboard for RDP Monitoring:
  
  ![7](./images/7.png)
  