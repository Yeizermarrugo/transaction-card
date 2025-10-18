const { APIGatewayProxyEvent, APIGatewayProxyResult } = require("aws-lambda");
const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const { Readable } = require("stream");
const csvParser = require("csv-parser");
const { getRedisClient } = require("../services/redis.js");

const s3Client = new S3Client({
  region: process.env.AWS_REGION || "us-east-2",
});
const BUCKET_NAME = process.env.S3_BUCKET || "";

console.log("ENV REDIS_ENDPOINT:", process.env.REDIS_ENDPOINT);
console.log("ENV REDIS_PORT:", process.env.REDIS_PORT);
console.log("ENV S3_BUCKET:", BUCKET_NAME);

interface ProductRecord {
  categoria: string;
  proveedor: string;
  servicio: string;
  plan: string;
  precio_mensual: string;
  detalles: string;
  estado: string;
}

// Helper function to parse CSV using csv-parser
const parseCsvContent = (csvContent: string): Promise<ProductRecord[]> => {
  return new Promise((resolve, reject) => {
    const records: ProductRecord[] = [];
    const stream = Readable.from([csvContent]);

    stream
      .pipe(csvParser({
        mapHeaders: ({ header }) => header.trim().toLowerCase(),
        mapValues: ({ value }) => value.trim()
      }))
      .on("data", (data) => {
        console.log("Raw CSV row parsed:", JSON.stringify(data));
        records.push(data);
      })
      .on("end", () => {
        console.log(CSV parsing complete. Total records: ${records.length});
        if (records.length > 0) {
          console.log("First record sample:", JSON.stringify(records[0]));
          console.log("Last record sample:", JSON.stringify(records[records.length - 1]));
        }
        resolve(records);
      })
      .on("error", (error) => {
        console.error("CSV parsing error:", error);
        reject(error);
      });
  });
};

export const handler = async (
  event: APIGatewayProxyEvent
): Promise<APIGatewayProxyResult> => {
  console.log("Event received:", JSON.stringify(event, null, 2));

  try {
    // 1. Obtener el contenido del CSV del body
    if (!event.body) {
      return {
        statusCode: 400,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ error: "CSV content is empty or missing" }),
      };
    }

    let csvContent: string;

    if (event.isBase64Encoded) {
      csvContent = Buffer.from(event.body, "base64").toString("utf-8");
    } else {
      csvContent = event.body;
    }

    console.log("CSV content length:", csvContent.length);
    console.log("CSV first 200 chars:", csvContent.substring(0, 200));

    // 2. Parsear el CSV
    const records = await parseCsvContent(csvContent);

    console.log(Parsed ${records.length} records from CSV);

    if (records.length === 0) {
      return {
        statusCode: 400,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ error: "No valid records found in CSV" }),
      };
    }

    // 3. Subir el CSV a S3
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
    const s3Key = catalogs/catalog-${timestamp}.csv;

    await s3Client.send(
      new PutObjectCommand({
        Bucket: BUCKET_NAME,
        Key: s3Key,
        Body: csvContent,
        ContentType: "text/csv",
        Metadata: {
          uploadedAt: new Date().toISOString(),
          recordCount: records.length.toString(),
        },
      })
    );

    console.log(CSV uploaded to S3: ${BUCKET_NAME}/${s3Key});

    // 4. Conectar a Redis
    const redisClient = await getRedisClient();
    console.log("Redis client connected successfully");

    // 5. Reemplazar completamente los datos en Redis
    console.log("Cleaning existing products from Redis...");

    const existingKeys = await redisClient.keys("catalog:product:*");

    if (existingKeys.length > 0) {
      await redisClient.del(existingKeys);
      console.log(
        Deleted ${existingKeys.length} existing product keys from Redis
      );
    }

    // 6. Insertar los nuevos productos en Redis usando pipeline
    console.log("Inserting new products into Redis...");

    const pipeline = redisClient.multi();

    records.forEach((record, index) => {
      const key = catalog:product:${index + 1};
      
      const productData = {
        categoria: record.categoria || "",
        proveedor: record.proveedor || "",
        servicio: record.servicio || "",
        plan: record.plan || "",
        precio_mensual: record.precio_mensual || "",
        detalles: record.detalles || "",
        estado: record.estado || "Activo",
      };

      console.log(Inserting key ${key}:, JSON.stringify(productData));
      pipeline.hSet(key, productData);
    });

    // Guardar metadata del catálogo
    pipeline.hSet("catalog:metadata", {
      lastUpdate: new Date().toISOString(),
      totalProducts: records.length.toString(),
      s3Key: s3Key,
      s3Bucket: BUCKET_NAME,
    });

    const results = await pipeline.exec();
    console.log(Pipeline executed. Results count: ${results?.length});
    console.log(Successfully inserted ${records.length} products into Redis);

    // 7. Verificar que se insertó correctamente (leer el primer producto)
    const firstProduct = await redisClient.hGetAll("catalog:product:1");
    console.log("Verification - First product in Redis:", JSON.stringify(firstProduct));

    await redisClient.quit();
    console.log("Redis client disconnected");

    // 8. Retornar respuesta exitosa
    return {
      statusCode: 200,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        message: "Catálogo actualizado exitosamente",
        stats: {
          s3Location: s3://${BUCKET_NAME}/${s3Key},
          productsUpdated: records.length,
          productsDeleted: existingKeys.length,
          timestamp: new Date().toISOString(),
        },
        sample: firstProduct, 
      }),
    };
  } catch (error) {
    console.error("Error updating catalog:", error);

    return {
      statusCode: 500,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        error: "Error al actualizar el catálogo",
        details: error instanceof Error ? error.message : String(error),
      }),
    };
  }
};