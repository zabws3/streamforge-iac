# StreamForge - Infrastructure as Code

Infrastructure as Code project developed using Terraform
and Docker.

## Overview

The objective of this project is to deploy and manage
a multi-environment web infrastructure using Terraform.

The infrastructure will include:

- Web application
- PostgreSQL database
- Redis cache
- Load Balancer
- Monitoring and centralized logging
- Shared file storage

## Environments

- Development (DEV)
- Production (PRO)

## Technologies

- Terraform
- Docker
- Python / Flask
- PostgreSQL
- Redis
- Nginx
- Prometheus
- Grafana
- MinIO

## Project Status

Initial project setup.

## Media storage

The MinIO container mounts the repository's `media/` directory read-only.
At startup it enables versioning on `streamforge-manifests` and
`streamforge-chunks`, then uploads `.mpd` files and `.m4s` segments while
preserving their relative paths. Existing objects are left untouched.

The web application retrieves manifests and segments from their respective
private buckets, so the manifest's relative segment URLs continue to work
through `/video/stream/`.

Check bucket versioning and uploaded objects with:

```sh
docker exec dev_minio mc version info streamforge/streamforge-manifests
docker exec dev_minio mc version info streamforge/streamforge-chunks
docker exec dev_minio mc find streamforge/streamforge-manifests
docker exec dev_minio mc find streamforge/streamforge-chunks
```
