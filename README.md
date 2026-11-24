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

### Upload a DASH video manually

Install the app dependencies on the host if they are not already installed,
then pass the local video folder to the uploader:

```sh
npm ci --prefix app
./app/scripts/upload-video.js /path/to/VideoFolder
```

The folder must contain `manifest.mpd` and at least one `.m4s` file. The
uploader stores them under `VideoFolder/` in their respective buckets and
verifies each uploaded object's size. It uses `MINIO_ENDPOINT` when set (or
`http://127.0.0.1:9000` by default) and reads credentials from
`MINIO_ACCESS_KEY`/`MINIO_SECRET_KEY` or the running `dev_minio` container.

Verify the uploaded keys with:

```sh
docker exec dev_minio mc find streamforge/streamforge-manifests/VideoFolder
docker exec dev_minio mc find streamforge/streamforge-chunks/VideoFolder
```
