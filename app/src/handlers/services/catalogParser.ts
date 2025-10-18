/**
 * Helper para extraer y parsear el archivo CSV desde un event de API Gateway.
 * - Soporta multipart/form-data (body base64 o plain)
 * - Soporta POST JSON con { csvBase64, filename } o { csv }
 * - Normaliza headers (snake_case, sin acentos ni espacios) y convierte números.
 */

const { Readable } = require("stream");
const csvParser = require("csv-parser");

/**
 * Normaliza cabecera a snake_case limpio.
 */
function normalizeHeader(h) {
  return h
    .normalize("NFKD") // remove accents
    .replace(/[^\w\s-]/g, "") // quitar chars raros
    .trim()
    .replace(/\s+/g, "_")
    .toLowerCase();
}

/**
 * Extrae parte file de multipart/form-data
 * Retorna { filename, contentType, buffer } o null si no encontró
 */
function extractFileFromMultipart(event) {
  const headers = event.headers || {};
  const contentType = headers["content-type"] || headers["Content-Type"] || "";
  if (!contentType.toLowerCase().includes("multipart/form-data")) return null;

  const boundaryMatch = contentType.match(/boundary=(?:"([^"]+)"|([^;]+))/i);
  if (!boundaryMatch) return null;
  const boundary = boundaryMatch[1] || boundaryMatch[2];

  // body puede venir base64 o raw
  const rawBody = event.isBase64Encoded
    ? Buffer.from(event.body || "", "base64")
    : Buffer.from(event.body || "", "utf8");

  // Convertimos a string para parse simple (CSV es texto)
  const bodyStr = rawBody.toString("latin1");

  const parts = bodyStr.split(`--${boundary}`);
  for (const part of parts) {
    if (!part || part === "--" || part.trim() === "") continue;
    // Encontrar headers y body (separado por doble CRLF)
    const index = part.indexOf("\r\n\r\n");
    if (index === -1) continue;
    const rawHeaders = part.slice(0, index);
    let content = part.slice(index + 4);

    // Content final suele terminar con CRLF, remover posible boundary trailing
    content = content.replace(/\r\n$/, "");

    // Buscar Content-Disposition filename
    const cdMatch = rawHeaders.match(/Content-Disposition:.*name="([^"]+)";\s*filename="([^"]+)"/i);
    if (!cdMatch) continue;
    const fieldName = cdMatch[1];
    const filename = cdMatch[2];

    const ctMatch = rawHeaders.match(/Content-Type:\s*([^\r\n]+)/i);
    const contentTypePart = ctMatch ? ctMatch[1].trim() : "application/octet-stream";

    // Retornar buffer en utf8 (CSV) usando latin1->utf8 para mantener bytes
    const fileBuffer = Buffer.from(content, "latin1");

    return {
      fieldName,
      filename,
      contentType: contentTypePart,
      buffer: fileBuffer,
    };
  }

  return null;
}

/**
 * Parse CSV desde Buffer y retorna array de objetos normalizados.
 */
function parseCsvBuffer(buffer) {
  return new Promise((resolve, reject) => {
    const results = [];
    // Convertir a UTF-8 y eliminar BOM si existe
    const utf8Str = buffer.toString("utf8").replace(/^\uFEFF/, "");
    const readable = Readable.from([utf8Str]);

    let normalizedHeaders = null;

    readable
      .pipe(csvParser())
      .on("headers", (headers) => {
        normalizedHeaders = headers.map((h) => normalizeHeader(h));
      })
      .on("data", (row) => {
        const normalized = {};
        Object.keys(row).forEach((origKey, idx) => {
          const key = normalizedHeaders ? normalizedHeaders[idx] || normalizeHeader(origKey) : normalizeHeader(origKey);
          let val = row[origKey];
          if (typeof val === "string") {
            val = val.trim();
            // intentar convertir a número si aplica (comas decimales convertidas)
            const maybeNum = Number(val.replace(/\s+/g, "").replace(",", "."));
            if (!Number.isNaN(maybeNum) && String(maybeNum) !== "") {
              normalized[key] = maybeNum;
            } else {
              normalized[key] = val;
            }
          } else {
            normalized[key] = val;
          }
        });
        results.push(normalized);
      })
      .on("end", () => resolve(results))
      .on("error", (err) => reject(err));
  });
}

/**
 * Entrada principal: recibe event (API Gateway) y retorna:
 * { filename, contentType, buffer, items }
 * - lanzará Error si no encuentra archivo o parsing falla
 */
async function parseCatalogFromEvent(event) {
  // Soportar JSON con csvBase64 o csv
  if (event.headers && (event.headers["content-type"] || event.headers["Content-Type"])?.includes("application/json")) {
    let bodyObj;
    try {
      bodyObj = typeof event.body === "string" ? JSON.parse(event.body) : event.body;
    } catch (err) {
      // seguir; tal vez body es raw csv
      bodyObj = null;
    }
    if (bodyObj && (bodyObj.csvBase64 || bodyObj.csv)) {
      const filename = bodyObj.filename || `catalog-${Date.now()}.csv`;
      const buffer = bodyObj.csvBase64 ? Buffer.from(bodyObj.csvBase64, "base64") : Buffer.from(bodyObj.csv, "utf8");
      const items = await parseCsvBuffer(buffer);
      return { filename, contentType: "text/csv", buffer, items };
    }
  }

  // Intentar multipart/form-data
  const filePart = extractFileFromMultipart(event);
  if (filePart) {
    const items = await parseCsvBuffer(filePart.buffer);
    return {
      filename: filePart.filename,
      contentType: filePart.contentType,
      buffer: filePart.buffer,
      items,
    };
  }

  // Si el body es puro CSV (text/csv), puede venir sin multipart
  const contentType = (event.headers && (event.headers["content-type"] || event.headers["Content-Type"])) || "";
  if (contentType.toLowerCase().includes("text/csv") || (!contentType && event.body && typeof event.body === "string")) {
    const buffer = event.isBase64Encoded ? Buffer.from(event.body, "base64") : Buffer.from(event.body, "utf8");
    const items = await parseCsvBuffer(buffer);
    const filename = `catalog-${Date.now()}.csv`;
    return { filename, contentType: "text/csv", buffer, items };
  }

  throw new Error("No se pudo extraer el archivo CSV del event (esperado multipart/form-data o JSON con csvBase64)");
}

module.exports = {
  parseCatalogFromEvent,
  parseCsvBuffer, // export por si quieres usar directamente
};