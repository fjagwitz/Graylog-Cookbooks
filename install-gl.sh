#!/bin/bash
sourcerepo="https://github.com/fjagwitz/Graylog-Cookbooks.git"
targetrepo="/opt"

# Create required Folders in the Filesystem
mkdir -p /opt/graylog/{archives,contentpacks,maxmind,nginx,prometheus}

# Create Environment Variables
