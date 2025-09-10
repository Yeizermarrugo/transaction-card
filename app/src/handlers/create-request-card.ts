const { DynamoDBClient, PutItemCommand } = require("@aws-sdk/client-dynamodb");
const crypto = require("crypto");

const CARD_TABLE = process.env.CARD_TABLE || "card-table";
const ddb = new DynamoDBClient({});

function generateScore(): number {
	return Math.floor(Math.random() * 101); // 0-100
}

function calculateAmount(score: number): number {
	return 100 + (score / 100) * (10000000 - 100);
}

exports.handler = async (event: any) => {
	console.log("event", event);
	const { userId, request } = JSON.parse(event.body);

	const uuid = crypto.randomUUID();
	const createdAt = new Date().toISOString();

	let item: any = {
		uuid: { S: uuid },
		user_id: { S: userId },
		type: { S: request },
		createdAt: { S: createdAt }
	};

	if (request === "CREDIT") {
		const score = generateScore();
		const amount = calculateAmount(score);
		item.status = { S: "PENDING" };
		item.balance = { N: amount.toString() };
		item.cupo = { N: amount.toString() };
		item.score = { N: score.toString() };
	} else {
		item.status = { S: "ACTIVATED" };
		item.balance = { N: "0" };
	}

	await ddb.send(new PutItemCommand({ TableName: CARD_TABLE, Item: item }));

	return { statusCode: 200, body: "Card request processed." };
};
