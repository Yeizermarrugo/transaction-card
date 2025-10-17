const AWS = require("aws-sdk");
const { createClient } = require("redis");
import type { RedisClientType } from "redis";

type CatalogItem = {
	id: number | string;
	categoria?: string;
	proveedor?: string;
	servicio?: string;
	plan?: string;
	precio_mensual?: number;
	detalles?: string;
	estado?: string;
	[key: string]: any;
};

const S3 = new AWS.S3();
const REDIS_HOST = process.env.REDIS_HOST!;
const REDIS_PORT = parseInt(process.env.REDIS_PORT || "6379", 10);
const CATALOG_BUCKET = process.env.CATALOG_BUCKET || process.env.mi_catalogo_servicios_bucket_2025 || process.env.mi_catalogo_servicios_bucket_2025;
const CATALOG_S3_KEY = process.env.CATALOG_S3_KEY || "catalog.csv";
const REDIS_KEY = process.env.CATALOG_REDIS_KEY || "catalog";

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

function parseCsvToObjects(csv: string): CatalogItem[] {
	// Simple CSV parser: expects header row, comma-separated, no quoted commas
	const lines = csv
		.split(/\r?\n/)
		.map((l) => l.trim())
		.filter((l) => l.length > 0);
	if (lines.length === 0) return [];
	const headerLine = lines[0];
	if (!headerLine) return [];
	const headers = headerLine.split(",").map((h) => h.trim());
	const items: CatalogItem[] = [];
	for (let i = 1; i < lines.length; i++) {
		const line = lines[i] ?? "";
		const cols = line.split(",").map((c) => c.trim());
		const obj: any = {};
		for (let j = 0; j < headers.length; j++) {
			const key = headers[j];
			const val = cols[j] ?? "";
			// skip empty header names
			if (!key) continue;
			// Try convert numeric fields
			const keyLower = key.toLowerCase();
			if (keyLower.includes("precio") || keyLower.includes("precio_mensual") || keyLower === "precio") {
				obj[key] = val === "" ? null : Number(val);
			} else if (keyLower === "id" || keyLower.endsWith("id")) {
				obj[key] = isNaN(Number(val)) ? val : Number(val);
			} else {
				obj[key] = val;
			}
		}
		items.push(obj as CatalogItem);
	}
	return items;
}
exports.handler = async (event: any) => {
	console.log("event", event);
	try {
		// Try Redis first
		try {
			await initRedis();
			if (redisClient) {
				const cached = await redisClient.get(REDIS_KEY);
				if (cached) {
					console.info("Catalog served from Redis");
					const json = JSON.parse(cached);
					return {
						statusCode: 200,
						headers: { "Content-Type": "application/json" },
						body: JSON.stringify(json)
					};
				}
			}
		} catch (err) {
			console.warn("Redis unavailable, falling back to S3:", err);
		}

		// Fallback: load CSV/JSON from S3
		if (!CATALOG_BUCKET) {
			console.log("CATALOG_BUCKET not configured");
			return { statusCode: 500, body: JSON.stringify({ message: "Configuration error: CATALOG_BUCKET not set" }) };
		}

		const obj = await S3.getObject({ Bucket: CATALOG_BUCKET, Key: CATALOG_S3_KEY }).promise();
		const body = obj.Body ? obj.Body.toString("utf-8") : "";

		let catalog: CatalogItem[] = [];
		try {
			const maybeJson = JSON.parse(body);
			if (Array.isArray(maybeJson)) catalog = maybeJson;
			else catalog = parseCsvToObjects(body);
		} catch {
			catalog = parseCsvToObjects(body);
		}

		// Cache into Redis best-effort
		try {
			if (redisClient) await redisClient.set(REDIS_KEY, JSON.stringify(catalog));
		} catch (e) {
			console.warn("Failed to cache catalog into Redis:", e);
		}

		return {
			statusCode: 200,
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify(catalog)
		};
	} catch (err) {
		console.log("get-catalog error:", err);
		return { statusCode: 500, body: JSON.stringify({ message: "Internal server error" }) };
	}
};
