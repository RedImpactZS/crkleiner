#!/usr/bin/env bash
podman run --rm --volume ./:/app $(podman build . --quiet) shards build --production --release --static
