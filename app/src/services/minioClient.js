const Minio = require("minio");

let client;

function getMinioClient() {
    if (client) return client;

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

    client = new Minio.Client({
        endPoint: parsedEndpoint.hostname,
        port: Number(parsedEndpoint.port) || undefined,
        useSSL: parsedEndpoint.protocol === "https:",
        accessKey,
        secretKey
    });

    return client;
}

function listMinioObjects(bucket, prefix = "") {
    return new Promise((resolve, reject) => {
        const objects = [];
        const stream = getMinioClient().listObjectsV2(bucket, prefix, true);

        stream.on("data", object => objects.push(object));
        stream.once("error", reject);
        stream.once("end", () => resolve(objects));
    });
}

function isMissingMinioObject(error) {
    return error?.code === "NoSuchKey" || error?.code === "NotFound";
}

module.exports = {
    getMinioClient,
    listMinioObjects,
    isMissingMinioObject
};
