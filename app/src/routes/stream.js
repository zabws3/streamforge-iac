
const express = require("express");
const fs = require("fs");
const path = require("path");
const { pipeline } = require("stream/promises");
const Minio = require("minio");

const router = express.Router();
let minioClient;

const MEDIA_PATH = path.resolve(
    process.env.MEDIA_PATH || "/var/zabflix/media"
);

const MIME_TYPES = {
    ".mpd": "application/dash+xml",
    ".m4s": "video/iso.segment",
    ".mp4": "video/mp4",
    ".m4a": "audio/mp4"
};

const MINIO_BUCKETS = {
    ".mpd": "streamforge-manifests",
    ".m4s": "streamforge-chunks"
};

function getMinioClient() {
    if (minioClient) return minioClient;

    const endpoint = process.env.MINIO_ENDPOINT;
    const accessKey = process.env.MINIO_ACCESS_KEY;
    const secretKey = process.env.MINIO_SECRET_KEY;

    if (!endpoint || !accessKey || !secretKey) {
        throw new Error(
            "MINIO_ENDPOINT, MINIO_ACCESS_KEY, and MINIO_SECRET_KEY must be configured."
        );
    }

    const parsedEndpoint = new URL(endpoint);
    if (!["http:", "https:"].includes(parsedEndpoint.protocol)) {
        throw new Error("MINIO_ENDPOINT must use http or https.");
    }

    minioClient = new Minio.Client({
        endPoint: parsedEndpoint.hostname,
        port: Number(parsedEndpoint.port) || undefined,
        useSSL: parsedEndpoint.protocol === "https:",
        accessKey,
        secretKey
    });

    return minioClient;
}

function parseByteRange(range, size) {
    const match = /^bytes=(\d*)-(\d*)$/.exec(range || "");
    if (!match || (!match[1] && !match[2])) return null;

    if (!match[1]) {
        const suffixLength = Number(match[2]);
        if (suffixLength <= 0 || size === 0) return { unsatisfiable: true };

        const length = Math.min(suffixLength, size);
        return { offset: size - length, length };
    }

    const offset = Number(match[1]);
    if (offset >= size) return { unsatisfiable: true };

    const end = match[2] ? Math.min(Number(match[2]), size - 1) : size - 1;
    if (end < offset) return { unsatisfiable: true };

    return { offset, length: end - offset + 1 };
}

async function streamFromMinio(req, res, bucket, requestedPath, extension) {
    try {
        const client = getMinioClient();
        const object = await client.statObject(bucket, requestedPath);
        const byteRange = req.headers.range
            ? parseByteRange(req.headers.range, object.size)
            : null;

        res.setHeader("Content-Type", MIME_TYPES[extension]);
        res.setHeader("Cache-Control", "private, no-store");
        res.setHeader("Accept-Ranges", "bytes");
        res.setHeader("ETag", object.etag);

        if (req.method === "HEAD") {
            res.setHeader("Content-Length", object.size);
            return res.end();
        }

        if (byteRange?.unsatisfiable) {
            res.status(416);
            res.setHeader("Content-Range", `bytes */${object.size}`);
            return res.end();
        }

        let mediaStream;
        if (byteRange) {
            const end = byteRange.offset + byteRange.length - 1;
            res.status(206);
            res.setHeader(
                "Content-Range",
                `bytes ${byteRange.offset}-${end}/${object.size}`
            );
            res.setHeader("Content-Length", byteRange.length);
            mediaStream = await client.getPartialObject(
                bucket,
                requestedPath,
                byteRange.offset,
                byteRange.length
            );
        } else {
            res.setHeader("Content-Length", object.size);
            mediaStream = await client.getObject(bucket, requestedPath);
        }

        await pipeline(mediaStream, res);
    } catch (error) {
        if (error.code === "NoSuchKey" || error.code === "NotFound") {
            return res.status(404).json({
                error: "Archivo multimedia no encontrado"
            });
        }

        if (res.destroyed) return;

        console.error(
            `MinIO media request failed for ${bucket}/${requestedPath}:`,
            error
        );
        if (!res.destroyed) {
            if (!res.headersSent) res.status(502).end();
        }
    }
}

router.get("/*filepath", async (req, res) => {
    const requestedPath = Array.isArray(req.params.filepath)
        ? req.params.filepath.join(path.sep)
        : req.params.filepath;

    console.log(`[DASH] ${req.method} ${req.originalUrl}`);
    console.log(`[DASH] Archivo solicitado: ${requestedPath}`);

    if (!requestedPath) {
        console.warn("[DASH] Petición sin ruta de archivo");

        return res.status(400).json({
            error: "Falta la ruta del archivo"
        });
    }

    const filePath = path.resolve(MEDIA_PATH, requestedPath);

    // Impedir que se acceda a archivos fuera de MEDIA_PATH.
    if (
        filePath !== MEDIA_PATH &&
        !filePath.startsWith(MEDIA_PATH + path.sep)
    ) {
        console.warn(`[DASH] Acceso denegado: ${requestedPath}`);

        return res.status(403).json({
            error: "Acceso denegado"
        });
    }

    const extension = path.extname(requestedPath).toLowerCase();
    const bucket = MINIO_BUCKETS[extension];

    if (bucket) {
        return streamFromMinio(req, res, bucket, requestedPath, extension);
    }

    fs.stat(filePath, (error, stats) => {
        if (error || !stats.isFile()) {
            console.warn(`[DASH] Archivo no encontrado: ${filePath}`);

            return res.status(404).json({
                error: "Archivo multimedia no encontrado"
            });
        }

        res.setHeader(
            "Content-Type",
            MIME_TYPES[extension] || "application/octet-stream"
        );

        res.setHeader("Cache-Control", "private, no-store");
        res.setHeader("Accept-Ranges", "bytes");

        console.log(
            `[DASH] Sirviendo ${requestedPath} (${stats.size} bytes)`
        );

        res.sendFile(filePath, sendError => {
            if (sendError) {
                console.error(
                    `[DASH] Error sirviendo ${requestedPath}:`,
                    sendError.message
                );

                if (!res.headersSent) {
                    res.status(sendError.statusCode || 500).end();
                }
            } else {
                console.log(`[DASH] Envío completado: ${requestedPath}`);
            }
        });
    });
});

module.exports = router;
