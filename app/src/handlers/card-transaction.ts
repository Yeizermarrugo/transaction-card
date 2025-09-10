const { DynamoDBClient, QueryCommand, GetItemCommand, PutItemCommand, UpdateItemCommand } = require("@aws-sdk/client-dynamodb");

const CARD_TABLE = process.env.CARD_TABLE || "card-table";
const TRANSACTION_TABLE = process.env.TRANSACTION_TABLE || "transaction-table";
const ddb = new DynamoDBClient({});

exports.handler = async (event: any) => {
	const cardId = event.pathParameters.cardId;
	const { merchant, amount } = JSON.parse(event.body);

	console.log("event: ", JSON.stringify(event));
	console.log("cardId: ", cardId);
	console.log("body: ", JSON.parse(event.body));
	console.log("merchant: ", merchant);
	console.log("amount: ", amount);

	// Obtiene tarjeta
	const cardRes = await ddb.send(
		new QueryCommand({
			TableName: CARD_TABLE,
			KeyConditionExpression: "#u = :id",
			ExpressionAttributeNames: { "#u": "uuid" },
			ExpressionAttributeValues: { ":id": { S: cardId } },
			ScanIndexForward: false,
			Limit: 1
		})
	);
	const card = cardRes.Items && cardRes.Items.length > 0 ? cardRes.Items[0] : null;
	if (!card || !card.type || card.type.S !== "DEBIT") return { statusCode: 400, body: "Only debit cards are allowed." };

	console.log("card: ", card);
	// Suma al balance
	const newBalance = parseFloat(card?.balance?.N ?? "0") + amount;
	console.log("New balance: ", newBalance);
	await ddb.send(
		new UpdateItemCommand({
			TableName: CARD_TABLE,
			Key: { uuid: { S: cardId }, createdAt: { S: card.createdAt.S } },
			UpdateExpression: "SET balance = :b",
			ExpressionAttributeValues: { ":b": { N: newBalance.toString() } }
		})
	);

	// Registra transacción
	await ddb.send(
		new PutItemCommand({
			TableName: TRANSACTION_TABLE,
			Item: {
				uuid: { S: crypto.randomUUID() },
				cardId: { S: cardId },
				amount: { N: amount.toString() },
				merchant: { S: merchant },
				type: { S: "SAVING" },
				createdAt: { S: card.createdAt.S }
			}
		})
	);

	return { statusCode: 200, body: "Balance added." };
};
