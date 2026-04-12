import postgres from "postgres";
import { drizzle } from "drizzle-orm/postgres-js";
import * as schema from "./schema";

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  throw new Error("DATABASE_URL environment variable is not set");
}

// Single connection pool shared across the app.
// postgres.js manages pooling internally.
const client = postgres(connectionString);

export const db = drizzle(client, { schema });

// Raw postgres.js client for data_dictionary and network_model queries (raw SQL only).
export const sql = client;
