const { DynamoDBClient, QueryCommand } = require("@aws-sdk/client-dynamodb");
const { PutObjectCommand, S3Client, GetObjectCommand } = require("@aws-sdk/client-s3");
const { getSignedUrl } = require("@aws-sdk/s3-request-presigner");

const TRANSACTION_TABLE = process.env.TRANSACTION_TABLE || "transaction-table";
const S3_BUCKET = process.env.REPORT_BUCKET || "mi-reporte-transacciones-bucket-2025";
const ddb = new DynamoDBClient({});
const s3 = new S3Client({});

function toCSV(transactions: any) {
	if (transactions.length === 0) return "";
	const headers = Object.keys(transactions[0]);
	const rows = transactions.map((tx: any) => headers.map((h) => tx[h]?.S || tx[h]?.N || "").join(","));
	return [headers.join(","), ...rows].join("\n");
}

module.exports.handler = async (event: any) => {
	const cardId = event.pathParameters?.cardId;
	const { start, end } = event.queryStringParameters || {};

	console.log("cardId", cardId);
	console.log("start", start);
	console.log("end", end);

	if (!cardId || !start || !end) {
		return {
			statusCode: 400,
			body: JSON.stringify({ error: "Missing cardId, start, or end parameter." })
		};
	}

	if (start > end) {
		return {
			statusCode: 400,
			body: JSON.stringify({ error: "start date must be less than or equal to end date" })
		};
	}

	const txRes = await ddb.send(
		new QueryCommand({
			TableName: TRANSACTION_TABLE,
			IndexName: "cardId-index",
			KeyConditionExpression: "cardId = :c",
			FilterExpression: "createdAt BETWEEN :start AND :end",
			ExpressionAttributeValues: {
				":c": { S: cardId },
				":start": { S: start },
				":end": { S: end }
			}
		})
	);

	const csv = toCSV(txRes.Items || []);
	const s3Key = `reports/${cardId}-${Date.now()}.csv`;

	await s3.send(
		new PutObjectCommand({
			Bucket: S3_BUCKET,
			Key: s3Key,
			Body: csv,
			ContentType: "text/csv"
		})
	);

	// Generar URL firmada (válida por 1 hora)
	const signedUrl = await getSignedUrl(
		s3,
		new GetObjectCommand({ Bucket: S3_BUCKET, Key: s3Key }),
		{ expiresIn: 3600 } // segundos
	);

	return {
		statusCode: 200,
		body: JSON.stringify({
			reportUrl: signedUrl
		})
	};
};
