#!/usr/bin/env tsx
/**
 * load-highways.ts — Load National Highways GeoJSON into network_model.object.
 *
 * Usage:
 *   tsx scripts/load-highways.ts --node <file> [<file>...]
 *   tsx scripts/load-highways.ts --link <file> [<file>...]
 *
 * Flags (mutually exclusive, one required):
 *   --node    Load features as Node objects (discriminator from properties.nodetype)
 *   --link    Load features as Link objects (discriminator from properties.linkcategory)
 *
 * DATABASE_URL is read from the environment or from apps/web/.env.local.
 * Existing records (matched by uuid or namespace+identity+valid_to) are silently skipped.
 */

import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import postgres from 'postgres';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT  = dirname(SCRIPT_DIR);
const ENV_FILE   = resolve(REPO_ROOT, 'apps/web/.env.local');
const NAMESPACE  = 'HIGHWAYS';
const BATCH_SIZE = 500;

// ── DATABASE_URL resolution ───────────────────────────────────────────────────

async function getDatabaseUrl(): Promise<string> {
  if (process.env.DATABASE_URL) return process.env.DATABASE_URL;
  try {
    const env = await readFile(ENV_FILE, 'utf8');
    const match = env.match(/^DATABASE_URL=(.+)$/m);
    if (match) return match[1].replace(/^['"]|['"]$/g, '');
  } catch {
    // file not found or unreadable
  }
  console.error(`ERROR: DATABASE_URL is not set and could not be read from ${ENV_FILE}`);
  process.exit(1);
}

// ── CLI arg parsing ───────────────────────────────────────────────────────────

function parseArgs(): { type: 'Node' | 'Link'; files: string[] } {
  const args = process.argv.slice(2);
  const hasNode = args.includes('--node');
  const hasLink = args.includes('--link');

  if (hasNode === hasLink) {
    console.error('ERROR: Specify exactly one of --node or --link.\n');
    console.error('Usage:');
    console.error('  tsx scripts/load-highways.ts --node <file> [<file>...]');
    console.error('  tsx scripts/load-highways.ts --link <file> [<file>...]');
    process.exit(1);
  }

  const files = args.filter(a => !a.startsWith('--'));
  if (files.length === 0) {
    console.error('ERROR: At least one input file must be specified.');
    process.exit(1);
  }

  return { type: hasNode ? 'Node' : 'Link', files };
}

// ── File reading with BOM detection ──────────────────────────────────────────
// GeoJSON exported from ArcGIS/Windows tools is commonly UTF-16 LE (BOM: FF FE).
// TextDecoder is used instead of Buffer.toString() because it handles BOM
// stripping natively (ignoreBOM defaults to false, meaning the BOM is consumed).

async function readTextFile(filePath: string): Promise<string> {
  const buf = await readFile(filePath);
  let text: string;
  // UTF-16 LE BOM: FF FE
  if (buf[0] === 0xff && buf[1] === 0xfe) {
    text = new TextDecoder('utf-16le').decode(buf);
  // UTF-16 BE BOM: FE FF
  } else if (buf[0] === 0xfe && buf[1] === 0xff) {
    text = new TextDecoder('utf-16be').decode(buf);
  } else {
    // UTF-8 (with or without BOM EF BB BF) — TextDecoder strips it automatically
    text = new TextDecoder('utf-8').decode(buf);
  }
  // Belt-and-braces: strip any U+FEFF that survives decoding
  return text.replace(/^\uFEFF/, '');
}

// ── Date parsing (RFC 1123 — e.g. "Wed, 06 Apr 2022 10:53:21 GMT") ───────────

function parseRfc1123(value: unknown): Date | null {
  if (!value || typeof value !== 'string') return null;
  const d = new Date(value);
  return isNaN(d.getTime()) ? null : d;
}

// ── Batch insert ──────────────────────────────────────────────────────────────

type RowPayload = {
  uuid: string;
  namespace: string;
  identity: string;
  class_name: string;
  discriminator: string | null;
  geo_geometry: string;                  // GeoJSON geometry serialised to string
  attributes: Record<string, unknown>;   // raw properties object (not pre-stringified)
  hash: string;
  valid_from: Date | null;
  valid_to: Date | null;
};

// One INSERT per row inside a single transaction.
// Avoids JSONB-array unpacking which has type-inference edge cases in postgres.js.
// COALESCE for valid_from because the column is NOT NULL.
async function insertBatch(
  sql: postgres.Sql,
  rows: RowPayload[],
): Promise<number> {
  if (rows.length === 0) return 0;
  let inserted = 0;
  await sql.begin(async sql => {
    for (const row of rows) {
      const result = await sql`
        INSERT INTO network_model.object
          (uuid, namespace, identity, class_name, discriminator,
           geo_geometry, sch_geometry, attributes, hash, valid_from, valid_to)
        VALUES (
          ${row.uuid}::uuid,
          ${row.namespace},
          ${row.identity},
          ${row.class_name},
          ${row.discriminator},
          ST_Force2D(ST_SetSRID(ST_GeomFromGeoJSON(${row.geo_geometry}), 4326)),
          NULL,
          ${sql.json(row.attributes)},
          ${row.hash},
          COALESCE(${row.valid_from}::timestamptz, NOW()),
          ${row.valid_to}::timestamptz
        )
        ON CONFLICT DO NOTHING
        RETURNING uuid
      `;
      inserted += result.length;
    }
  });
  return inserted;
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  const { type, files } = parseArgs();
  const discriminatorField = type === 'Node' ? 'nodetype' : 'linkcategory';

  const dbUrl = await getDatabaseUrl();
  const sql   = postgres(dbUrl, { max: 1 });

  let totalAttempted = 0;
  let totalInserted  = 0;
  let filesProcessed = 0;

  for (const filePath of files) {
    const absPath = resolve(filePath);
    console.log(`Processing ${absPath} ...`);

    let raw: string;
    try {
      raw = await readTextFile(absPath);
    } catch (err) {
      console.warn(`  WARN: Could not read ${absPath}: ${(err as Error).message}`);
      continue;
    }

    let collection: { features?: unknown[] };
    try {
      collection = JSON.parse(raw) as { features?: unknown[] };
    } catch (err) {
      console.warn(`  WARN: Could not parse JSON in ${absPath}: ${(err as Error).message}`);
      continue;
    }

    if (!Array.isArray(collection.features)) {
      console.warn(`  WARN: No features array in ${absPath}, skipping.`);
      continue;
    }

    const features = collection.features as Array<{
      geometry: object;
      properties: Record<string, unknown>;
    }>;

    const total = features.length;
    let fileInserted = 0;

    for (let i = 0; i < total; i += BATCH_SIZE) {
      const batch = features.slice(i, i + BATCH_SIZE);

      const rows: RowPayload[] = batch.map(feature => {
        const props = feature.properties ?? {};
        return {
          uuid:          String(props.globalid ?? ''),
          namespace:     NAMESPACE,
          identity:      String(props.toid ?? ''),
          class_name:    type,
          discriminator: props[discriminatorField] != null
                           ? String(props[discriminatorField])
                           : null,
          geo_geometry:  JSON.stringify(feature.geometry),
          attributes:    props,
          hash:          createHash('md5').update(JSON.stringify(props)).digest('hex'),
          valid_from:    parseRfc1123(props.startdate),
          valid_to:      parseRfc1123(props.enddate),
        };
      });

      const inserted = await insertBatch(sql, rows);
      const skipped  = rows.length - inserted;

      totalAttempted += rows.length;
      totalInserted  += inserted;
      fileInserted   += inserted;

      const batchNum = Math.floor(i / BATCH_SIZE) + 1;
      const batchTotal = Math.ceil(total / BATCH_SIZE);
      console.log(`  Batch ${batchNum}/${batchTotal}: ${inserted} inserted, ${skipped} skipped`);
    }

    console.log(`  File total: ${fileInserted} inserted from ${total} features`);
    filesProcessed++;
  }

  await sql.end();

  const skipped = totalAttempted - totalInserted;
  console.log('');
  console.log(
    `Done: ${filesProcessed} file(s) processed — ` +
    `${totalAttempted} attempted, ${totalInserted} inserted, ${skipped} skipped.`,
  );
}

main().catch(err => {
  console.error('ERROR:', (err as Error).message ?? err);
  process.exit(1);
});
