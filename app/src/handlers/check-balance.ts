const AWS = require("aws-sdk");
import type { DocumentClient } from "aws-sdk/clients/dynamodb";
import type { RedisClientType } from "redis";
const { createClient } = require("redis");

const ddb = new AWS.DynamoDB.DocumentClient();
const sqs = new AWS.SQS();

const TRANSACTION_TABLE = process.env.TRANSACTION_TABLE_NAME!;
const CARD_TABLE = process.env.CARD_TABLE_NAME!;
const NEXT_QUEUE_URL = process.env.SQS_TRANSACTION_URL!; // transaction queue
const REDIS_HOST = process.env.REDIS_HOST;
const REDIS_PORT = parseInt(process.env.REDIS_PORT || "6379", 10);
const REDIS_TTL = Number(process.env.REDIS_TTL_SECONDS || 86400);

let redisClient: RedisClientType | null = null;

async function getBalanceForCard(cardId: string): Promise<number> {
	let balance = 0;
	let ExclusiveStartKey: DocumentClient.Key | undefined = undefined;

	const paramsBase: DocumentClient.QueryInput = {
		TableName: CARD_TABLE,
		IndexName: "cardId-index",
		KeyConditionExpression: "cardId = :c",
		ExpressionAttributeValues: { ":c": cardId },
		ProjectionExpression: "amount"
	};

	do {
		const res = await ddb.query({ ...paramsBase, ExclusiveStartKey }).promise();
		const items = res.Items || [];
		for (const it of items) balance += Number(it.amount ?? 0);
		ExclusiveStartKey = res.LastEvaluatedKey as DocumentClient.Key | undefined;
	} while (ExclusiveStartKey);

	return balance;
}

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

async function handleSqsPayload(payload: any) {
	const { traceId, cardId, service } = payload;
	if (!traceId || !cardId) {
		console.warn("Invalid payload, missing traceId/cardId", payload);
		return;
	}
	const cacheKey = `trace:${traceId}`;

	// Idempotency via Redis
	if (redisClient) {
		const existing = await redisClient.get(cacheKey);
		if (existing) {
			try {
				const p = JSON.parse(existing);
				if (p?.status === "FINISH" || p?.status === "IN_PROGRESS") return;
			} catch {}
		}
	}

	// Compute balance by cardId
	const balance = await getBalanceForCard(cardId);
	const price = Number(service?.precio_mensual ?? 0);

	if (balance >= price) {
		// mark in-progress
		const now = Date.now();
		await ddb
			.update({
				TableName: TRANSACTION_TABLE,
				Key: { uuid: traceId },
				UpdateExpression: "SET #s = :s, updatedAt = :u",
				ExpressionAttributeNames: { "#s": "status" },
				ExpressionAttributeValues: { ":s": "IN_PROGRESS", ":u": now }
			})
			.promise();

		if (redisClient) await redisClient.set(cacheKey, JSON.stringify({ ...payload, status: "IN_PROGRESS", timestamp: Date.now() }), { EX: REDIS_TTL });

		// send to transaction queue
		await sqs.sendMessage({ QueueUrl: NEXT_QUEUE_URL, MessageBody: JSON.stringify(payload), DelaySeconds: 5 }).promise();
		console.info("check-balance: enqueued for transaction", traceId);
	} else {
		// insufficient funds
		const errMsg = "La cuenta no tiene saldo disponible";
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

		console.info("check-balance: marked FAILED", traceId);
	}
}

exports.handler = async (event: any) => {
	console.info("check-balance invoked", JSON.stringify(event).substring(0, 1000));
	try {
		await initRedis().catch((e) => console.warn("Redis init err:", e?.message || e));
		for (const record of event.Records) {
			try {
				const payload = typeof record.body === "string" ? JSON.parse(record.body) : record.body;
				await handleSqsPayload(payload);
			} catch (err) {
				console.error("Error processing record:", err, "record:", record);
				throw err; // allow SQS retry for transient errors
			}
		}
		return { statusCode: 200, body: "ok" } as any;
	} catch (err) {
		console.error("Unhandled error in check-balance:", err);
		throw err;
	}
};
