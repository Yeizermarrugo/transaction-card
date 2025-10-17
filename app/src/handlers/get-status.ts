const AWS = require("aws-sdk");
const { createClient } = require("redis");
import type { RedisClientType } from "redis";

const ddb = new AWS.DynamoDB.DocumentClient();
const REDIS_HOST = process.env.REDIS_HOST;
const REDIS_PORT = parseInt(process.env.REDIS_PORT || "6379", 10);
const TRANSACTION_TABLE = process.env.TRANSACTION_TABLE_NAME!;

let redisClient: RedisClientType | null = null;
async function initRedis() {
	if (!REDIS_HOST) return;
	if (!redisClient) {
		const client = createClient({ socket: { host: REDIS_HOST, port: REDIS_PORT } });
		client.on("error", (err: any) => console.warn("Redis error:", err));
		await client.connect();
		redisClient = client;
	} else if (!redisClient.isOpen) {
		await redisClient.connect();
	}
}

exports.handler = async (event:any) => {
	console.info("get-status invoked", event);
	try {
		const traceId = event.pathParameters?.traceId || event.queryStringParameters?.traceId;
		if (!traceId) return { statusCode: 400, body: JSON.stringify({ message: "traceId missing" }) };

		// Try Redis first
		await initRedis().catch(() => {});
		if (redisClient) {
			const v = await redisClient.get(`trace:${traceId}`);
			if (v) {
				return { statusCode: 200, headers: { "Content-Type": "application/json" }, body: v };
			}
		}

		// Fallback to DynamoDB
		const res = await ddb.get({ TableName: TRANSACTION_TABLE, Key: { uuid: traceId } }).promise();
		if (!res.Item) return { statusCode: 404, body: JSON.stringify({ message: "trace not found" }) };
		return { statusCode: 200, headers: { "Content-Type": "application/json" }, body: JSON.stringify(res.Item) };
	} catch (err) {
		console.error("get-status error:", err);
		return { statusCode: 500, body: JSON.stringify({ message: "Internal server error" }) };
	}
};
