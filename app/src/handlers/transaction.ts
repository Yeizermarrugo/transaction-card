const AWS = require("aws-sdk");
import https = require("https");
import type { RedisClientType } from "redis";
const { URL } = require("url");
const { createClient } = require("redis");

const ddb = new AWS.DynamoDB.DocumentClient();
const REDIS_HOST = process.env.REDIS_HOST;
const REDIS_PORT = parseInt(process.env.REDIS_PORT || "6379", 10);
const TRANSACTION_TABLE = process.env.TRANSACTION_TABLE_NAME!;
const CARD_TABLE = process.env.CARD_TABLE_NAME!;
const CORE_API_URL = process.env.CORE_API_URL!; // e.g. https://core.example.com/transactions/purchase
const CORE_API_KEY = process.env.CORE_API_KEY; // optional
const REDIS_TTL = Number(process.env.REDIS_TTL_SECONDS || 86400);

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

function postJson(urlStr: string, body: any): Promise<{ statusCode: number; body: string }> {
	return new Promise((resolve, reject) => {
		const url = new URL(urlStr);
		const data = JSON.stringify(body);
		const opts: https.RequestOptions = {
			method: "POST",
			hostname: url.hostname,
			path: url.pathname + (url.search || ""),
			port: url.port || 443,
			headers: {
				"Content-Type": "application/json",
				"Content-Length": Buffer.byteLength(data),
				...(CORE_API_KEY ? { "x-api-key": CORE_API_KEY } : {})
			}
		};
		const req = https.request(opts, (res) => {
			let resp = "";
			res.on("data", (d) => (resp += d));
			res.on("end", () => resolve({ statusCode: res.statusCode || 500, body: resp }));
		});
		req.on("error", (e) => reject(e));
		req.write(data);
		req.end();
	});
}

async function handle(payload: any) {
	const { traceId, cardId, service } = payload;
	if (!traceId) return;
	const cacheKey = `trace:${traceId}`;
	// Attempt to debit in core
	const amount = Number(service?.precio_mensual ?? 0);

	try {
		const corePayload = { merchant: payload.merchant || "unknown", cardId, amount };
		const resp = await postJson(CORE_API_URL, corePayload);

		if (resp.statusCode >= 200 && resp.statusCode < 300) {
			// success
			const now = Date.now();
			await ddb
				.update({
					TableName: TRANSACTION_TABLE,
					Key: { uuid: traceId },
					UpdateExpression: "SET #s = :s, updatedAt = :u, coreResponse = :r",
					ExpressionAttributeNames: { "#s": "status" },
					ExpressionAttributeValues: { ":s": "FINISH", ":u": now, ":r": resp.body }
				})
				.promise();

			if (redisClient) await redisClient.set(cacheKey, JSON.stringify({ ...payload, status: "FINISH", coreResponse: resp.body, timestamp: now }), { EX: REDIS_TTL });
			console.info("transaction: FINISH", traceId);
		} else {
			// bank returned error
			const errMsg = `Core error ${resp.statusCode}: ${resp.body}`;
			const now = Date.now();
			await ddb
				.update({
					TableName: TRANSACTION_TABLE,
					Key: { uuid: traceId },
					UpdateExpression: "SET #s = :s, #e = :e, updatedAt = :u",
					ExpressionAttributeNames: { "#s": "status", "#e": "error" },
					ExpressionAttributeValues: { ":s": "FAILED", ":e": errMsg, ":u": now }
				})
				.promise();
			if (redisClient) await redisClient.set(cacheKey, JSON.stringify({ ...payload, status: "FAILED", error: errMsg, timestamp: now }), { EX: REDIS_TTL });
			console.warn("transaction: FAILED due to core error", traceId, errMsg);
		}
	} catch (err) {
		console.error("transaction: unexpected error", err);
		// Throw to let SQS retry if transient
		throw err;
	}
}

exports.handler = async (event: any) => {
	console.info("transaction invoked", JSON.stringify(event).substring(0, 1000));
	try {
		await initRedis().catch((e) => console.warn("Redis init:", e?.message || e));
		for (const r of event.Records) {
			const payload = typeof r.body === "string" ? JSON.parse(r.body) : r.body;
			await handle(payload);
		}
		return { statusCode: 200, body: "ok" } as any;
	} catch (err) {
		console.error("transaction handler error:", err);
		throw err;
	}
};
