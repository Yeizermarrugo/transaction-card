const { DynamoDBClient, QueryCommand, UpdateItemCommand } = require("@aws-sdk/client-dynamodb");

const CARD_TABLE = process.env.CARD_TABLE || "card-table";
const TRANSACTION_TABLE = process.env.TRANSACTION_TABLE || "transaction-table";
const ddb = new DynamoDBClient({});

exports.handler = async (event: any) => {
	const { userId } = JSON.parse(event.body);

	console.log("event: ", JSON.parse(event.body));
	console.log("userId", userId);

	// Busca tarjetas del usuario
	const cardRes = await ddb.send(
		new QueryCommand({
			TableName: CARD_TABLE,
			IndexName: "user_id-index",
			KeyConditionExpression: "user_id = :u",
			ExpressionAttributeValues: { ":u": { S: userId } }
		})
	);

	console.log("QueryCommand input: ", {
		TableName: CARD_TABLE,
		IndexName: "user_id-index",
		KeyConditionExpression: "user_id = :u",
		ExpressionAttributeValues: { ":u": { S: userId } }
	});
	console.log(
		"command: ",
		new QueryCommand({
			TableName: CARD_TABLE,
			IndexName: "user_id-index",
			KeyConditionExpression: "user_id = :u",
			ExpressionAttributeValues: { ":u": { S: userId } }
		})
	);
	console.log("cardRes: ", cardRes);

	const card = cardRes.Items?.[0];
	console.log("card: ", card);
	if (!card) return { statusCode: 404, body: "Card not found" };
	if (!card.uuid || !card.uuid.S) return { statusCode: 500, body: "Card UUID missing" };

	console.log("txRes1: ", {
		TableName: TRANSACTION_TABLE,
		IndexName: "cardId-index",
		KeyConditionExpression: "cardId = :c",
		ExpressionAttributeValues: { ":c": { S: card.uuid.S } }
	});
	// Busca transacciones de esa tarjeta
	const txRes = await ddb.send(
		new QueryCommand({
			TableName: TRANSACTION_TABLE,
			IndexName: "cardId-index",
			KeyConditionExpression: "cardId = :c",
			ExpressionAttributeValues: { ":c": { S: card.uuid.S } }
		})
	);

	console.log("txRes2: ", txRes);

	if ((txRes.Count ?? 0) >= 10) {
		await ddb.send(
			new UpdateItemCommand({
				TableName: CARD_TABLE,
				Key: { uuid: { S: card.uuid.S }, createdAt: { S: card.createdAt.S } },
				UpdateExpression: "SET #status = :a",
				ExpressionAttributeNames: { "#status": "status" },
				ExpressionAttributeValues: { ":a": { S: "ACTIVATED" } }
			})
		);
		return { statusCode: 200, body: "Card activated!" };
	} else {
		return { statusCode: 400, body: "Not enough transactions to activate." };
	}
};
