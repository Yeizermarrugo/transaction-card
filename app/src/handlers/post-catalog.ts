const { PutObjectCommand, S3Client } = require("@aws-sdk/client-s3");
const csvParser = require("csv-parser");
const { createClient } = require("redis");
const { Readable } = require("stream");
import type { RedisClientType } from "redis";

const s3 = new S3Client({});
const REDIS_HOST = process.env.REDIS_HOST || "";
const REDIS_PORT = process.env.REDIS_PORT || "6379";
const REDIS_KEY = process.env.CATALOG_REDIS_KEY || "catalog";
const CATALOG_BUCKET = process.env.CATALOG_BUCKET || "mi-catalogo-servicios-bucket-2025";
let redisClient: RedisClientType | null = null;

async function initRedis() {
	if (!REDIS_HOST) return;
	if (!redisClient) {
		const client = createClient({
			socket: { host: REDIS_HOST, port: REDIS_PORT }
		});
		client.on("error", (err: any) => console.warn("Redis error:", err));
		await client.connect();
		redisClient = client;
	} else if (!redisClient.isOpen) {
		await redisClient.connect();
	}
}

function extractCatalogFile(event: any) {
	// Extraer boundary y buffer crudo del body enviado por API Gateway
	const contentType = event.headers["content-type"] || event.headers["Content-Type"] || "";
	if (!contentType.includes("multipart/form-data")) return null;
	const boundary = contentType.split("boundary=")[1];
	// El body debe llegar como base64 (recomendado) o latin1 (si se configuró así)
	const buffer = Buffer.from(event.body, event.isBase64Encoded ? "base64" : "latin1");
	const parts = buffer.toString().split(`--${boundary}`);
	for (const part of parts) {
		if (part.includes("Content-Disposition") && part.includes('name="catalog"') && part.includes("filename=")) {
			const filenameMatch = /filename="(.+?)"/.exec(part);
			const fileMimeMatch = /Content-Type: (.+)/.exec(part);
			if (!filenameMatch || !fileMimeMatch) continue;
			const filename = filenameMatch[1];
			const fileMime = fileMimeMatch[1];
			// Extrae el contenido binario (csv) entre los headers y el siguiente boundary
			const fileMatch = part.match(/\r\n\r\n([\s\S]*?)\r\n$/);
			if (!fileMatch) continue;
			const fileBuffer = Buffer.from(fileMatch[1], "utf8"); // Si el encoding no funciona, prueba "latin1"
			return { filename, fileMime, fileBuffer };
		}
	}
	return null;
}

function parseCsvFromBuffer(buffer: any) {
	return new Promise((resolve, reject) => {
		const results = [];
		const utf8Str = buffer.toString("utf8").replace(/^\uFEFF/, "");
		const readable = Readable.from([utf8Str]);
		let headersMap = null;
		readable
			.pipe(csvParser())
			.on("headers", (headers) => {
				headersMap = headers.map((h) =>
					h
						.replace(/\s+/g, "_")
						.replace(/[^\w_]/g, "")
						.toLowerCase()
				);
			})
			.on("data", (data) => {
				const normalized = {};
				Object.keys(data).forEach((k, idx) => {
					const nk = headersMap ? headersMap[idx] || k : k;
					let val = data[k];
					if (typeof val === "string") {
						const cleaned = val.trim();
						const normalizedNum = cleaned.replace(/\s+/g, "").replace(",", ".");
						const num = Number(normalizedNum);
						val = !Number.isNaN(num) && normalizedNum !== "" ? num : cleaned;
					}
					normalized[nk] = val;
				});
				results.push(normalized);
			})
			.on("end", () => resolve(results))
			.on("error", (err) => reject(err));
	});
}

exports.handler = async (event: any) => {
	try {
		const fileObj = extractCatalogFile(event);
		if (!fileObj) {
			return { statusCode: 400, body: JSON.stringify({ message: "No se encontró archivo catalog en el body" }) };
		}

		const s3Key = `catalog/${fileObj.filename}`;
		await s3.send(
			new PutObjectCommand({
				Bucket: CATALOG_BUCKET,
				Key: s3Key,
				Body: fileObj.fileBuffer,
				ContentType: fileObj.fileMime || "text/csv"
			})
		);

		const parsedItems = await parseCsvFromBuffer(fileObj.fileBuffer);
		const jsonKey = s3Key.replace(/(\.csv)?$/i, ".json");
		await s3.send(
			new PutObjectCommand({
				Bucket: CATALOG_BUCKET,
				Key: jsonKey,
				Body: JSON.stringify(parsedItems, null, 2),
				ContentType: "application/json"
			})
		);

		await initRedis();
		if (redisClient) {
			await redisClient.set(REDIS_KEY, JSON.stringify(parsedItems));
			await redisClient.quit();
		}

		return {
			statusCode: 200,
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({
				message: "Catálogo actualizado correctamente.",
				items: parsedItems.length,
				s3Key,
				jsonKey
			})
		};
	} catch (err) {
		return {
			statusCode: 500,
			body: JSON.stringify({ message: "Error procesando archivo", error: err.message })
		};
	}
};
