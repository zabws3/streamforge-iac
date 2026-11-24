
const express = require("express");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { pipeline } = require("stream/promises");
const {
    getMinioClient,
    isMissingMinioObject
} = require("../services/minioClient");

const router = express.Router();

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

function logMediaResponse(req, res, requestedPath, bucket) {
    let logged = false;

    const log = outcome => {
        if (logged) return;
        logged = true;

        console.log(JSON.stringify({
            event: "media_stream",
            outcome,
            server_instance: os.hostname(),
            request_host: req.get("host") || null,
            client_ip: req.get("x-real-ip") || req.socket.remoteAddress || null,
            method: req.method,
            object: requestedPath,
            bucket,
            storage: res.locals.mediaStorage || "unknown",
            status: res.statusCode,
            content_length: Number(res.getHeader("Content-Length")) || 0,
            range: req.get("range") || null
        }));
    };

    res.once("finish", () => log("complete"));
    res.once("close", () => {
        if (!res.writableFinished) log("aborted");
    });
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
        res.locals.mediaStorage = "minio";
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
        if (isMissingMinioObject(error)) {
            return streamFromLocal(req, res, requestedPath, extension);
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

function streamFromLocal(req, res, requestedPath, extension) {
    const filePath = path.resolve(MEDIA_PATH, requestedPath);

    if (
        filePath !== MEDIA_PATH &&
        !filePath.startsWith(MEDIA_PATH + path.sep)
    ) {
        return res.status(403).json({ error: "Acceso denegado" });
    }

    res.locals.mediaStorage = "local";

    fs.stat(filePath, (error, stats) => {
        if (error || !stats.isFile()) {
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
        res.sendFile(filePath, sendError => {
            if (sendError) {
                console.error(
                    `[DASH] Error sirviendo ${requestedPath}:`,
                    sendError.message
                );

                if (!res.headersSent) {
                    res.status(sendError.statusCode || 500).end();
                }
            }
        });
    });
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
    logMediaResponse(req, res, requestedPath, bucket || null);

    if (bucket) {
        return streamFromMinio(req, res, bucket, requestedPath, extension);
    }

    return streamFromLocal(req, res, requestedPath, extension);
});

module.exports = router;
