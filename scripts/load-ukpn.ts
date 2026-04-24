#!/usr/bin/env tsx
/**
 * load-ukpn.ts — Load a UKPN GeoJSON file into network_model.object.
 *
 * Usage:
 *   tsx scripts/load-ukpn.ts --file <path> --prefix <prefix> --class <class_name> --discriminator <value>
 *
 * Examples:
 *   tsx scripts/load-ukpn.ts --file data/ukpn-132kv-overhead-lines.geojson \
 *       --prefix UKPN-OHL-132 --class OverheadLine --discriminator 132kV
 *   tsx scripts/load-ukpn.ts --file data/ukpn-132kv-poles-towers.geojson \
 *       --prefix UKPN-SUP-132 --class Support --discriminator 132kV
 *
 * Identity: uses the feature's `id` property when present, otherwise the
 * sequential index within the file. Format: {prefix}-{id|index}
 *
 * DATABASE_URL is read from the environment or from apps/web/.env.local.
 * Existing records (namespace + identity, valid_to IS NULL) are silently skipped.
 */

import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import postgres from 'postgres';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT  = dirname(SCRIPT_DIR);
const ENV_FILE   = resolve(REPO_ROOT, 'apps/web/.env.local');
const NAMESPACE  = 'ELECTRICITY';
const BATCH_SIZE = 200;

// ── Argument parsing ──────────────────────────────────────────────────────────

function getArg(flag: string): string {
  const idx = process.argv.indexOf(flag);
  if (idx === -1 || !process.argv[idx + 1]) {
    console.error(`ERROR: ${flag} <value> is required`);
    console.error('Usage: tsx scripts/load-ukpn.ts --file <path> --prefix <prefix> --class <class_name> --discriminator <value>');
    process.exit(1);
  }
  return process.argv[idx + 1];
}

const inputFile      = resolve(REPO_ROOT, getArg('--file'));
const identityPrefix = getArg('--prefix');
const className      = getArg('--class');
const discriminator  = getArg('--discriminator');

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

// ── File reading with BOM detection ──────────────────────────────────────────

async function readTextFile(filePath: string): Promise<string> {
  const buf = await readFile(filePath);
  let text: string;
  if (buf[0] === 0xff && buf[1] === 0xfe) {
    text = new TextDecoder('utf-16le').decode(buf);
  } else if (buf[0] === 0xfe && buf[1] === 0xff) {
    text = new TextDecoder('utf-16be').decode(buf);
  } else {
    text = new TextDecoder('utf-8').decode(buf);
  }
  return text.replace(/^﻿/, '');
}

// ── Batch insert ──────────────────────────────────────────────────────────────

type RowPayload = {
  identity:     string;
  geo_geometry: string;
  attributes:   Record<string, unknown>;
  hash:         string;
};

async function insertBatch(sql: postgres.Sql, rows: RowPayload[]): Promise<number> {
  if (rows.length === 0) return 0;
  let inserted = 0;
  await sql.begin(async sql => {
    for (const row of rows) {
      const result = await sql`
        INSERT INTO network_model.object
          (namespace, identity, class_name, discriminator,
           geo_geometry, sch_geometry, attributes, hash)
        SELECT
          ${NAMESPACE},
          ${row.identity},
          ${className},
          ${discriminator},
          ST_Force2D(ST_SetSRID(ST_GeomFromGeoJSON(${row.geo_geometry}), 4326)),
          NULL,
          ${sql.json(row.attributes)},
          ${row.hash}
        WHERE NOT EXISTS (
          SELECT 1 FROM network_model.object
          WHERE namespace = ${NAMESPACE}
            AND identity  = ${row.identity}
            AND valid_to IS NULL
        )
        RETURNING uuid
      `;
      inserted += result.length;
    }
  });
  return inserted;
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  const dbUrl = await getDatabaseUrl();
  const sql   = postgres(dbUrl, { max: 1 });

  console.log(`Reading ${inputFile} ...`);

  const raw = await readTextFile(inputFile);

  const collection = JSON.parse(raw) as { features?: unknown[] };
  if (!Array.isArray(collection.features)) {
    console.error('ERROR: No features array found in GeoJSON.');
    process.exit(1);
  }

  const features = collection.features as Array<{
    geometry: object;
    properties: Record<string, unknown>;
  }>;

  const total = features.length;
  console.log(`Found ${total} features. Loading as ${className} / ${discriminator} (prefix: ${identityPrefix}) ...`);

  let totalAttempted = 0;
  let totalInserted  = 0;

  for (let i = 0; i < total; i += BATCH_SIZE) {
    const batch = features.slice(i, i + BATCH_SIZE);

    const rows: RowPayload[] = batch.map((feature, batchIdx) => {
      const props    = feature.properties ?? {};
      // Use the feature's `id` property when available; fall back to global index.
      const featureId = props.id != null ? String(props.id) : String(i + batchIdx);
      return {
        identity:     `${identityPrefix}-${featureId}`,
        geo_geometry: JSON.stringify(feature.geometry),
        attributes:   props,
        hash:         createHash('md5').update(JSON.stringify(props)).digest('hex'),
      };
    });

    const inserted = await insertBatch(sql, rows);
    const skipped  = rows.length - inserted;

    totalAttempted += rows.length;
    totalInserted  += inserted;

    const batchNum   = Math.floor(i / BATCH_SIZE) + 1;
    const batchTotal = Math.ceil(total / BATCH_SIZE);
    console.log(`  Batch ${batchNum}/${batchTotal}: ${inserted} inserted, ${skipped} skipped`);
  }

  await sql.end();

  const skipped = totalAttempted - totalInserted;
  console.log('');
  console.log(`Done: ${totalAttempted} attempted, ${totalInserted} inserted, ${skipped} skipped.`);
}

main().catch(err => {
  console.error('ERROR:', (err as Error).message ?? err);
  process.exit(1);
});
