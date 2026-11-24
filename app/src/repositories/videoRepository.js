const db = require("../db");

async function getVideoById(id) {
    const [rows] = await db.query(
        `SELECT
            video_id AS id,
            title,
            description,
            duration_seconds AS durationSeconds,
            thumbnail_url AS thumbnailUrl,
            mpd_path AS mpdPath,
            category_id AS categoryId,
            upload_date AS uploadDate
         FROM videos
         WHERE video_id = ?`,
        [id]
    );

    return rows[0] || null;
}

async function getVideoByMpdPath(mpdPath) {
    const [rows] = await db.query(
        `SELECT video_id AS id
         FROM videos
         WHERE mpd_path = ?
         LIMIT 1`,
        [mpdPath]
    );

    return rows[0] || null;
}

async function getAllVideos() {
    const [rows] = await db.query(
        `SELECT
            video_id AS id,
            title,
            description,
            duration_seconds AS durationSeconds,
            thumbnail_url AS thumbnailUrl,
            mpd_path AS mpdPath,
            category_id AS categoryId,
            upload_date AS uploadDate
         FROM videos
         ORDER BY upload_date DESC`
    );

    return rows;
}

async function searchVideos(title, description, categoryId) {
    let query = `
        SELECT
            video_id AS id,
            title,
            description,
            duration_seconds AS durationSeconds,
            thumbnail_url AS thumbnailUrl,
            mpd_path AS mpdPath,
            category_id AS categoryId,
            upload_date AS uploadDate
        FROM videos
        WHERE 1 = 1
    `;

    const params = [];

    if (title) {
        query += " AND title LIKE ?";
        params.push(`%${title}%`);
    }

    if (description) {
        query += " AND description LIKE ?";
        params.push(`%${description}%`);
    }

    if (categoryId) {
        query += " AND category_id = ?";
        params.push(categoryId);
    }

    query += " ORDER BY upload_date DESC";

    const [rows] = await db.query(query, params);

    return rows;
}

async function getVideosByCategory(categoryId) {
    const [rows] = await db.query(
        `SELECT
            video_id AS id,
            title,
            description,
            duration_seconds AS durationSeconds,
            thumbnail_url AS thumbnailUrl,
            mpd_path AS mpdPath,
            category_id AS categoryId,
            upload_date AS uploadDate
         FROM videos
         WHERE category_id = ?
         ORDER BY upload_date DESC`,
        [categoryId]
    );

    return rows;
}

async function createVideo(video) {
    const connection = await db.getConnection();
    let lockAcquired = false;

    try {
        const [lockRows] = await connection.query(
            "SELECT GET_LOCK(?, 10) AS acquired",
            ["streamforge:video-catalog"]
        );

        if (Number(lockRows[0].acquired) !== 1) {
            const error = new Error("Timed out waiting to register the video.");
            error.code = "ER_LOCK_WAIT_TIMEOUT";
            throw error;
        }
        lockAcquired = true;

        const [existing] = await connection.query(
            "SELECT video_id FROM videos WHERE mpd_path = ? LIMIT 1",
            [video.mpdPath]
        );

        if (existing.length > 0) {
            return null;
        }

        const [result] = await connection.query(
            `INSERT INTO videos
                (title, description, duration_seconds, thumbnail_url, mpd_path, category_id)
             VALUES (?, ?, ?, ?, ?, ?)`,
            [
                video.title,
                video.description,
                video.durationSeconds,
                video.thumbnailUrl,
                video.mpdPath,
                video.categoryId
            ]
        );

        return result.insertId;
    } finally {
        if (lockAcquired) {
            try {
                await connection.query(
                    "SELECT RELEASE_LOCK(?)",
                    ["streamforge:video-catalog"]
                );
            } catch (error) {
                console.error("Could not release video catalog lock:", error);
            }
        }
        connection.release();
    }
}

async function updateVideo(id, video) {
    const [result] = await db.query(
        `UPDATE videos
         SET
            title = ?,
            description = ?,
            duration_seconds = ?,
            thumbnail_url = ?,
            mpd_path = ?,
            category_id = ?
         WHERE video_id = ?`,
        [
            video.title,
            video.description,
            video.durationSeconds,
            video.thumbnailUrl,
            video.mpdPath,
            video.categoryId,
            id
        ]
    );

    return result.affectedRows > 0;
}

async function deleteVideo(id) {
    const [result] = await db.query(
        `DELETE FROM videos
         WHERE video_id = ?`,
        [id]
    );

    return result.affectedRows > 0;
}

async function countVideos() {
    const [rows] = await db.query(
        `SELECT COUNT(*) AS count
         FROM videos`
    );

    return rows[0].count;
}

async function countVideosByCategory(categoryId) {
    const [rows] = await db.query(
        `SELECT COUNT(*) AS count
         FROM videos
         WHERE category_id = ?`,
        [categoryId]
    );

    return rows[0].count;
}

module.exports = {
    getVideoById,
    getVideoByMpdPath,
    getAllVideos,
    searchVideos,
    getVideosByCategory,
    createVideo,
    updateVideo,
    deleteVideo,
    countVideos,
    countVideosByCategory
};