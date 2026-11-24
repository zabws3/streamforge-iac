#!/usr/bin/env node

const { execFileSync } = require("child_process");
const fs = require("fs/promises");
const path = require("path");
const Minio = require("minio");

const BUCKETS = {
    manifest: "streamforge-manifests",
    chunks: "streamforge-chunks"
};

function getCredentials() {
    const accessKey = process.env.MINIO_ACCESS_KEY;
    const secretKey = process.env.MINIO_SECRET_KEY;

    if (accessKey && secretKey) {
        return { accessKey, secretKey };
    }

    if (accessKey || secretKey) {
        throw new Error(
            "Set both MINIO_ACCESS_KEY and MINIO_SECRET_KEY, or leave both unset to read them from Docker."
        );
    }

    const container = process.env.MINIO_CONTAINER || "dev_minio";
    let containerEnv;

    try {
        containerEnv = execFileSync(
            "docker",
            [
                "inspect",
                "--format",
                "{{range .Config.Env}}{{println .}}{{end}}",
                container
            ],
            { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }
        );
    } catch {
        throw new Error(
            `Could not read MinIO credentials from Docker container "${container}". ` +
            "Set MINIO_ACCESS_KEY and MINIO_SECRET_KEY, or start MinIO."
        );
    }

    const values = Object.fromEntries(
        containerEnv
            .split(/\r?\n/)
            .filter(line => line.startsWith("MINIO_ROOT_USER=") ||
                line.startsWith("MINIO_ROOT_PASSWORD="))
            .map(line => {
                const separator = line.indexOf("=");
                return [line.slice(0, separator), line.slice(separator + 1)];
            })
    );

    if (!values.MINIO_ROOT_USER || !values.MINIO_ROOT_PASSWORD) {
        throw new Error(
            `MinIO credentials are missing from Docker container "${container}".`
        );
    }

    return {
        accessKey: values.MINIO_ROOT_USER,
        secretKey: values.MINIO_ROOT_PASSWORD
    };
}

async function collectChunks(directory) {
    const files = [];
    const entries = await fs.readdir(directory, { withFileTypes: true });

    for (const entry of entries) {
        const absolutePath = path.join(directory, entry.name);
        if (entry.isDirectory()) {
            files.push(...await collectChunks(absolutePath));
        } else if (entry.isFile() && path.extname(entry.name) === ".m4s") {
            files.push(absolutePath);
        }
    }

    return files;
}

function objectKey(videoName, videoDirectory, filePath) {
    const relativePath = path.relative(videoDirectory, filePath);
    return path.posix.join(videoName, ...relativePath.split(path.sep));
}

async function main() {
    const inputDirectory = process.argv[2];
    if (!inputDirectory || process.argv.length > 3) {
        throw new Error(
            "Usage: ./app/scripts/upload-video.js <video-directory>"
        );
    }

    const videoDirectory = path.resolve(inputDirectory);
    const directoryInfo = await fs.stat(videoDirectory).catch(() => null);
    if (!directoryInfo?.isDirectory()) {
        throw new Error(`Video directory not found: ${videoDirectory}`);
    }

    const videoName = path.basename(videoDirectory);
    if (!videoName) {
        throw new Error("Could not determine the video folder name.");
    }

    const manifestPath = path.join(videoDirectory, "manifest.mpd");
    const manifestInfo = await fs.stat(manifestPath).catch(() => null);
    if (!manifestInfo?.isFile()) {
        throw new Error(`Required manifest not found: ${manifestPath}`);
    }

    const chunkPaths = await collectChunks(videoDirectory);
    if (chunkPaths.length === 0) {
        throw new Error(`No .m4s chunks found in ${videoDirectory}`);
    }

    const uploads = [
        {
            bucket: BUCKETS.manifest,
            filePath: manifestPath,
            key: path.posix.join(videoName, "manifest.mpd"),
            size: manifestInfo.size
        },
        ...await Promise.all(
            chunkPaths.map(async filePath => ({
                bucket: BUCKETS.chunks,
                filePath,
                key: objectKey(videoName, videoDirectory, filePath),
                size: (await fs.stat(filePath)).size
            }))
        )
    ];

    console.log(`Video: ${videoName}`);
    console.log("Files to upload:");
    for (const upload of uploads) {
        console.log(`  ${upload.bucket}/${upload.key}`);
    }

    const endpoint = new URL(process.env.MINIO_ENDPOINT || "http://127.0.0.1:9000");
    if (!["http:", "https:"].includes(endpoint.protocol)) {
        throw new Error("MINIO_ENDPOINT must use http or https.");
    }

    const client = new Minio.Client({
        endPoint: endpoint.hostname,
        port: Number(endpoint.port) || undefined,
        useSSL: endpoint.protocol === "https:",
        ...getCredentials()
    });

    for (const bucket of Object.values(BUCKETS)) {
        if (!await client.bucketExists(bucket)) {
            throw new Error(
                `Required bucket "${bucket}" does not exist. Create it through the existing MinIO initialization.`
            );
        }
    }

    for (const upload of uploads) {
        console.log(`Uploading ${upload.filePath} -> ${upload.bucket}/${upload.key}`);
        await client.fPutObject(upload.bucket, upload.key, upload.filePath);

        const storedObject = await client.statObject(upload.bucket, upload.key);
        if (storedObject.size !== upload.size) {
            throw new Error(
                `Verification failed for ${upload.bucket}/${upload.key}: ` +
                `expected ${upload.size} bytes, found ${storedObject.size}.`
            );
        }

        console.log(`  OK (${storedObject.size} bytes; verified in MinIO)`);
    }

    console.log(`Upload complete: ${uploads.length} objects stored under "${videoName}/".`);
}

main().catch(error => {
    console.error(`Upload failed: ${error.message}`);
    process.exitCode = 1;
});
