/**
 * Helper Redis (singleton) para Lambdas.
 * - Evita reconnects en invocaciones warm.
 * - Usa createClient de 'redis' (v4).
 * - Llama getRedisClient() para obtener cliente conectado.
 */

const { createClient } = require("redis");
let client = null;

async function getRedisClient() {
  if (client && client.isOpen) return client;

  const REDIS_HOST = process.env.REDIS_HOST || process.env.REDIS_ENDPOINT || "";
  const REDIS_PORT = process.env.REDIS_PORT ? Number(process.env.REDIS_PORT) : 6379;
  const REDIS_PASSWORD = process.env.REDIS_PASSWORD || undefined;

  if (!REDIS_HOST) {
    throw new Error("REDIS_HOST no configurado en las variables de entorno");
  }

  if (!client) {
    client = createClient({
      socket: { host: REDIS_HOST, port: REDIS_PORT },
      password: REDIS_PASSWORD,
    });
    client.on("error", (err) => {
      console.warn("[redis] error:", err);
    });
    client.on("connect", () => {
      console.info("[redis] connecting...");
    });
    client.on("ready", () => {
      console.info("[redis] ready");
    });
  }

  if (!client.isOpen) {
    await client.connect();
  }

  return client;
}

/**
 * Cierra la conexión (opcional).
 */
async function closeRedisClient() {
  if (client && client.isOpen) {
    try {
      await client.quit();
    } catch (err) {
      try { client.disconnect(); } catch (e) {}
    } finally {
      client = null;
    }
  }
}

module.exports = { getRedisClient, closeRedisClient };