const { DynamoDBClient, QueryCommand, PutItemCommand, UpdateItemCommand } = require("@aws-sdk/client-dynamodb");

const CARD_TABLE = process.env.CARD_TABLE || "card-table";
const TRANSACTION_TABLE = process.env.TRANSACTION_TABLE || "transaction-table";
const ddb = new DynamoDBClient({});

exports.handler = async (event: any) => {
	const { merchant, cardId, amount } = JSON.parse(event.body);

	// Busca el registro actual (toma el más reciente por uuid)
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
	if (!card) return { statusCode: 404, body: "Card not found" };

	let balance = parseFloat(card.balance?.N ?? "0");
	let type = card.type?.S;
	let status = card.status?.S;

	if (!amount || amount <= 0) return { statusCode: 400, body: "Amount must be greater than zero." };
	if (!merchant) return { statusCode: 400, body: "Merchant is required." };

	if (!type) return { statusCode: 400, body: "Card type is missing." };

	if (type === "DEBIT") {
		if (balance < amount) return { statusCode: 400, body: "Insufficient balance." };
		balance -= amount;
	} else if (type === "CREDIT") {
		if (status !== "ACTIVE") return { statusCode: 400, body: "Card is not active." };
		if (balance < amount) return { statusCode: 400, body: "Exceeds credit limit." };
		balance -= amount;
	}

	// Actualiza balance (usa SIEMPRE ambos keys)
	const updateParams = {
		TableName: CARD_TABLE,
		Key: { uuid: { S: cardId }, createdAt: { S: card.createdAt.S } },
		UpdateExpression: "SET balance = :b",
		ExpressionAttributeValues: { ":b": { N: balance.toString() } }
	};

	console.log("updateParams: ", updateParams);

	await ddb.send(new UpdateItemCommand(updateParams));

	// Registra transacción
	await ddb.send(
		new PutItemCommand({
			TableName: TRANSACTION_TABLE,
			Item: {
				uuid: { S: crypto.randomUUID() },
				cardId: { S: cardId },
				amount: { N: amount.toString() },
				merchant: { S: merchant },
				type: { S: "PURCHASE" },
				createdAt: { S: new Date().toISOString() }
			}
		})
	);

	return { statusCode: 200, body: "Purchase registered." };
};
