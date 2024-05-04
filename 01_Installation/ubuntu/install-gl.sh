#!/bin/bash
sourcerepo="https://github.com/fjagwitz/Graylog-Cookbooks.git"
targetrepo="/opt"

# Create required Folders in the Filesystem
mkdir   "/opt/graylog/archives" \
        "/opt/graylog/contentpacks" \ 
        "/opt/graylog/maxmind" \
        "/opt/graylog/nginx" \
        "/opt/graylog/prometheus"

# Create Environment Variables
