#!/bin/bash
# A script to download this entire site with wget
wget \
  --recursive \
  --page-requisites \
  --convert-links \
  --no-clobber \
  --wait=2 \
  --limit-rate=20K \
  --domains ysyx.oscc.cc \
  --no-parent \
  https://ysyx.oscc.cc/docs/ics-pa/
