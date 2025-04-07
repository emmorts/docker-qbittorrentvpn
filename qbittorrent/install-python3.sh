#!/bin/bash
if [ ! -e /usr/bin/python3 ]; then
	echo "[INFO] Python3 not yet installed, installing..." | ts '%Y-%m-%d %H:%M:%.S'
	apk --no-cache add python3 \
	&& rm -rf /var/cache/apk/*
else
	echo "[INFO] Python3 is already installed, nothing to do." | ts '%Y-%m-%d %H:%M:%.S'
fi