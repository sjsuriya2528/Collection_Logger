const db = require('./db');

async function migrate() {
  try {
    console.log('Running migration: Adding cash_amount and upi_amount...');
    await db.query('ALTER TABLE collections ADD COLUMN IF NOT EXISTS cash_amount NUMERIC DEFAULT 0');
    await db.query('ALTER TABLE collections ADD COLUMN IF NOT EXISTS upi_amount NUMERIC DEFAULT 0');
    console.log('Migration successful!');
    process.exit(0);
  } catch (err) {
    console.error('Migration failed:', err);
    process.exit(1);
  }
}

migrate();
