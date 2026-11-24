const { createClient } = require("redis");

const client = createClient({
    socket: {
        host: process.env.REDIS_HOST,
        port: process.env.REDIS_PORT
    }
});

client.on("error", (error) => {
    console.error("Redis error:", error);
});

async function connectRedis() {
    if (!client.isOpen) {
        await client.connect();
    }
}

async function invalidateVideoCache() {
    if (!process.env.REDIS_HOST) return;

    try {
        await connectRedis();

        for await (const batch of client.scanIterator({
            MATCH: "videos:*",
            COUNT: 100
        })) {
            const keys = Array.isArray(batch) ? batch : [batch];
            if (keys.length > 0) {
                await client.del(keys);
            }
        }
    } catch (error) {
        console.error("Could not invalidate video cache:", error);
    }
}

module.exports = {
    client,
    connectRedis,
    invalidateVideoCache
};
