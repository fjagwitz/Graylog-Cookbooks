# Graylog Professionals: Windows - RDP Monitoring

## Requirements

- Graylog 6.0.2 or higher
- Graylog Enterprise or Security License
- Illuminate 5.1 or higher

## How to install

- Upload and [Install](https://graylog.org/videos/content-packs/) the Content Pack in Graylog (the video is for Graylog v3.0 but it does still work the same way)
- Go to _"SYSTEM" / "CONTENT PACKS"_, filter for "pro" and klick on "Install":
  
  ![1](./images/1.png)
- Go to _"SYSTEM" / "PIPELINES"_, filter for "pro" and klick on "Edit":

  ![2](./images/2.png)
- Klick on "Edit connections":
  
  ![3](./images/3.png)
- Choose "Illuminate: Windows Security Event Log Messages" and "Update connections":

  ![4](./images/4.png)
- Validate your settings and ensure the UI shows "This pipeline is processing messages from the stream "Illuminate:Windows Security Event Log Messages":
  
  ![5](./images/5.png)
- Go to _"DASHBOARDS"_, filter for "pro" and choose __"Graylog Professionals: Windows - RDP Monitoring"__:

  ![6](./images/6.png)
