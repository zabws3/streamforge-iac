
const express = require("express");
const path = require("path");
const fs = require("fs/promises");

const videoRepository = require("../repositories/videoRepository");
const { invalidateVideoCache } = require("../cache");
const {
    getMinioClient,
    isMissingMinioObject,
    listMinioObjects
} = require("../services/minioClient");
const requireAdmin = require("../middleware/requireAdmin");

const router = express.Router();
const MANIFEST_BUCKET = "streamforge-manifests";

router.use(requireAdmin);

router.get("/categories", async (req, res) => {
    try {
        const db = require("../db");
        const [rows] = await db.query(
            "SELECT category_id AS id, name FROM categories ORDER BY name"
        );

        res.json({ data: rows });
    } catch (error) {
        console.error("Admin categories error:", error);
        res.status(500).json({
            error: "No se pudieron obtener las categorías."
        });
    }
});



function validateVideo(body) {
    const title = typeof body.title === "string"
        ? body.title.trim()
        : "";

    const description = typeof body.description === "string"
        ? body.description.trim()
        : "";

    const thumbnailUrl = typeof body.thumbnailUrl === "string"
        ? body.thumbnailUrl.trim()
        : "";

    const mpdPath = typeof body.mpdPath === "string"
        ? body.mpdPath.trim().replaceAll("\\", "/")
        : "";

    const durationSeconds = Number(body.durationSeconds);
    const categoryId = body.categoryId === "" ||
        body.categoryId === null ||
        body.categoryId === undefined
        ? null
        : Number(body.categoryId);

    if (!title || title.length > 200) {
        return { error: "El título es obligatorio y debe tener como máximo 200 caracteres." };
    }

    if (description.length > 20000) {
        return { error: "La descripción es demasiado larga." };
    }

    if (!Number.isInteger(durationSeconds) || durationSeconds < 1) {
        return { error: "La duración debe ser un entero positivo en segundos." };
    }

    if (thumbnailUrl && (
        thumbnailUrl.length > 500 ||
        !/^https?:\/\/\S+$/i.test(thumbnailUrl)
    )) {
        return { error: "La portada debe ser una URL HTTP o HTTPS válida." };
    }

    if (
        !mpdPath ||
        mpdPath.length > 500 ||
        path.isAbsolute(mpdPath) ||
        mpdPath.includes(":") ||
        mpdPath.split("/").some(part =>
            !part || part === "." || part === ".."
        )
    ) {
        return { error: "Indica una ruta MPD relativa válida, por ejemplo Cortometraje/manifest.mpd." };
    }

    if (
        categoryId !== null &&
        (!Number.isInteger(categoryId) || categoryId < 1)
    ) {
        return { error: "La categoría no es válida." };
    }

    return {
        video: {
            title,
            description: description || null,
            durationSeconds,
            thumbnailUrl: thumbnailUrl || null,
            mpdPath,
            categoryId
        }
    };
}

async function validateMpdExists(mpdPath) {
    const mediaRoot = path.resolve(
        process.env.MEDIA_PATH || "/var/zabflix/media"
    );

    const manifestPath = path.resolve(mediaRoot, mpdPath);

    if (!manifestPath.startsWith(mediaRoot + path.sep)) {
        return false;
    }

    try {
        const stat = await fs.stat(manifestPath);
        if (stat.isFile()) return true;
    } catch (error) {
        if (error.code !== "ENOENT") throw error;
    }

    try {
        await getMinioClient().statObject(MANIFEST_BUCKET, mpdPath);
        return true;
    } catch (error) {
        if (isMissingMinioObject(error)) return false;
        throw error;
    }
}

// GET /api/admin/minio-videos
router.get("/minio-videos", async (req, res) => {
    let objects;
    try {
        objects = await listMinioObjects(MANIFEST_BUCKET);
    } catch (error) {
        console.error("Admin MinIO manifest list error:", error);
        res.status(502).json({
            error: "No se pudieron consultar los manifiestos almacenados en MinIO."
        });
        return;
    }

    let catalogVideos;
    try {
        catalogVideos = await videoRepository.getAllVideos();
    } catch (error) {
        console.error("Admin catalog lookup for MinIO manifests failed:", error);
        res.status(500).json({
            error: "No se pudo comprobar qué manifiestos ya están en el catálogo."
        });
        return;
    }

    const registeredPaths = new Set(
        catalogVideos.map(video => video.mpdPath.toLowerCase())
    );
    const videos = objects
        .filter(object => object.name.endsWith("/manifest.mpd"))
        .map(object => {
            const mpdPath = object.name;
            const prefix = mpdPath.slice(0, -"/manifest.mpd".length);
            const pathParts = prefix.split("/");

            if (
                !prefix ||
                mpdPath.includes("\\") ||
                pathParts.some(part =>
                    !part || part === "." || part === ".."
                )
            ) {
                return null;
            }

            return {
                name: pathParts[pathParts.length - 1],
                mpdPath,
                registered: registeredPaths.has(mpdPath.toLowerCase())
            };
        })
        .filter(Boolean)
        .sort((left, right) => left.name.localeCompare(right.name));

    res.json({ data: videos });
});

// GET /api/admin/videos
router.get("/videos", async (req, res) => {
    try {
        const videos = await videoRepository.getAllVideos();
        res.json({ data: videos });
    } catch (error) {
        console.error("Admin list videos error:", error);
        res.status(500).json({ error: "No se pudieron obtener los vídeos." });
    }
});

// POST /api/admin/videos
router.post("/videos", async (req, res) => {
    try {
        const result = validateVideo(req.body);

        if (result.error) {
            return res.status(400).json({ error: result.error });
        }

        if (await videoRepository.getVideoByMpdPath(result.video.mpdPath)) {
            return res.status(409).json({
                error: "Este manifiesto ya está registrado en el catálogo."
            });
        }

        if (!await validateMpdExists(result.video.mpdPath)) {
            return res.status(400).json({
                error: "No se encuentra el manifiesto MPD ni en MinIO ni en el directorio de medios."
            });
        }

        const id = await videoRepository.createVideo(result.video);
        if (!id) {
            return res.status(409).json({
                error: "Este manifiesto ya está registrado en el catálogo."
            });
        }
        const video = await videoRepository.getVideoById(id);
        await invalidateVideoCache();

        res.status(201).json({ data: video });
    } catch (error) {
        console.error("Admin create video error:", error);
        res.status(500).json({ error: "No se pudo crear el vídeo." });
    }
});

// PUT /api/admin/videos/:id
router.put("/videos/:id", async (req, res) => {
    try {
        const id = Number(req.params.id);

        if (!Number.isInteger(id) || id < 1) {
            return res.status(400).json({ error: "ID no válido." });
        }

        const result = validateVideo(req.body);

        if (result.error) {
            return res.status(400).json({ error: result.error });
        }

        const registeredVideo = await videoRepository.getVideoByMpdPath(
            result.video.mpdPath
        );
        if (registeredVideo && Number(registeredVideo.id) !== id) {
            return res.status(409).json({
                error: "Este manifiesto ya está asociado a otro vídeo del catálogo."
            });
        }

        if (!await validateMpdExists(result.video.mpdPath)) {
            return res.status(400).json({
                error: "No se encuentra el manifiesto MPD ni en MinIO ni en el directorio de medios."
            });
        }

        const updated = await videoRepository.updateVideo(id, result.video);

        if (!updated) {
            const existing = await videoRepository.getVideoById(id);

            if (!existing) {
                return res.status(404).json({ error: "Vídeo no encontrado." });
            }
        }

        const video = await videoRepository.getVideoById(id);
        await invalidateVideoCache();
        res.json({ data: video });
    } catch (error) {
        console.error("Admin update video error:", error);
        res.status(500).json({ error: "No se pudo actualizar el vídeo." });
    }
});

// DELETE /api/admin/videos/:id
router.delete("/videos/:id", async (req, res) => {
    try {
        const id = Number(req.params.id);

        if (!Number.isInteger(id) || id < 1) {
            return res.status(400).json({ error: "ID no válido." });
        }

        const deleted = await videoRepository.deleteVideo(id);

        if (!deleted) {
            return res.status(404).json({ error: "Vídeo no encontrado." });
        }

        await invalidateVideoCache();
        res.json({ message: "Vídeo eliminado correctamente." });
    } catch (error) {
        console.error("Admin delete video error:", error);
        res.status(500).json({ error: "No se pudo eliminar el vídeo." });
    }
});

module.exports = router;