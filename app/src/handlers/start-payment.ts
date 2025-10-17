const AWS = require("aws-sdk");
const redis = require("redis");
const { v4: uuidv4 } = require("uuid");

const ddb = new AWS.DynamoDB.DocumentClient();
const sqs = new AWS.SQS();

const CARD_TABLE = process.env.CARD_TABLE_NAME!;
const TRANSACTION_TABLE = process.env.TRANSACTION_TABLE_NAME!;
const CHECK_BALANCE_QUEUE_URL = process.env.SQS_CHECK_BALANCE_URL!; // queue to trigger check-balance
const SQS_START_QUEUE_URL = process.env.SQS_START_PAYMENT_URL; // optional
const TRACE_TTL_MS = Number(process.env.TRACE_TTL_MS || 24 * 60 * 60 * 1000); // for Redis if used

/**
 * POST /payment  or POST /card/transaction/{cardId}
 * Body:
 * {
 *   "cardId": "uuid",
 *   "service": { ... }
 * }
 *
 * Returns: { traceId: "uuid" }
 */
exports.handler = async (event: any) => {
	console.info("start-payment invoked", event);
	try {
		if (!event.body) return { statusCode: 400, body: JSON.stringify({ message: "Empty body" }) };
		const body = JSON.parse(event.body);
		const cardId = body.cardId || event.pathParameters?.cardId;
		const service = body.service;
		if (!cardId || !service) return { statusCode: 400, body: JSON.stringify({ message: "cardId and service required" }) };

		// Validate card exists in card_table
		const cardRes = await ddb.get({ TableName: CARD_TABLE, Key: { uuid: cardId } }).promise();
		if (!cardRes.Item) {
			return { statusCode: 404, body: JSON.stringify({ message: "Card not found" }) };
		}
		const userId = cardRes.Item.user_id;

		// Create traceId and initial transaction record
		const traceId = uuidv4();
		const timestamp = Date.now();

		const initialRecord = {
			uuid: traceId,
			cardId,
			userId,
			service,
			status: "INITIAL",
			error: null,
			createdAt: timestamp,
			updatedAt: timestamp
		};

		// Persist initial record
		await ddb.put({ TableName: TRANSACTION_TABLE, Item: initialRecord }).promise();

		// Enqueue to check-balance queue (payload includes traceId)
		const payload = JSON.stringify(initialRecord);
		await sqs.sendMessage({ QueueUrl: CHECK_BALANCE_QUEUE_URL, MessageBody: payload, DelaySeconds: 5 }).promise();

		// Optionally also enqueue to a start queue if your flow needs it
		if (SQS_START_QUEUE_URL) {
			await sqs
				.sendMessage({ QueueUrl: SQS_START_QUEUE_URL, MessageBody: payload })
				.promise()
				.catch(() => {});
		}

		return { statusCode: 200, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ traceId }) };
	} catch (err) {
		console.error("start-payment error:", err);
		return { statusCode: 500, body: JSON.stringify({ message: "Internal server error" }) };
	}
};
