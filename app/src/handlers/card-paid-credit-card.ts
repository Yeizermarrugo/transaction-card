const { DynamoDBClient, QueryCommand, PutItemCommand, UpdateItemCommand } = require("@aws-sdk/client-dynamodb");
const crypto = require("crypto");

const CARD_TABLE = process.env.CARD_TABLE || "card-table";
const TRANSACTION_TABLE = process.env.TRANSACTION_TABLE || "transaction-table";
const ddb = new DynamoDBClient({});

exports.handler = async (event: any) => {
	const { merchant, cardId, amount } = JSON.parse(event.body);

	// Busca la tarjeta
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
	let cupo = parseFloat(card.cupo?.N ?? "0");
	let type = card.type?.S;
	if (!type) return { statusCode: 400, body: "Card type is missing." };

	if (type !== "CREDIT") {
		return { statusCode: 400, body: "Only credit card payments are allowed." };
	}

	// Calcula deuda actual
	const debt = cupo - balance;

	if (debt === 0) {
		return { statusCode: 400, body: "Card is already fully paid." };
	}

	if (amount > debt) {
		return { statusCode: 400, body: `You must pay exactly $${debt}.` };
	}

	// Suma el pago al balance
	const newBalance = balance + amount;
	const remainingDebt = cupo - newBalance;

	// Actualiza balance
	await ddb.send(
		new UpdateItemCommand({
			TableName: CARD_TABLE,
			Key: {
				uuid: { S: cardId },
				createdAt: { S: card.createdAt.S }
			},
			UpdateExpression: "SET balance = :b",
			ExpressionAttributeValues: { ":b": { N: newBalance.toString() } }
		})
	);

	// Registra la transacción
	await ddb.send(
		new PutItemCommand({
			TableName: TRANSACTION_TABLE,
			Item: {
				uuid: { S: crypto.randomUUID() },
				cardId: { S: cardId },
				amount: { N: amount.toString() },
				merchant: { S: merchant },
				type: { S: "PAYMENT_BALANCE" },
				createdAt: { S: new Date().toISOString() }
			}
		})
	);

	let message;
	if (remainingDebt === 0) {
		message = "Card is now fully paid.";
	} else {
		message = `Payment registered. Paid: $${amount}. Remaining debt: $${remainingDebt}.`;
	}

	return {
		statusCode: 200,
		body: JSON.stringify({
			paid: amount,
			remaining_debt: remainingDebt,
			message
		})
	};
};
