const { Client } = require('pg');
require('dotenv').config();

const client = new Client({
  user: process.env.DB_USER,
  host: process.env.DB_HOST,
  database: process.env.DB_NAME,
  password: process.env.DB_PASSWORD,
  port: process.env.DB_PORT,
});

async function check() {
  await client.connect();
  const res = await client.query(`
    SELECT t.token, u.email, u.role 
    FROM fcm_tokens t
    JOIN users u ON t.user_id = u.id
  `);
  console.log(JSON.stringify(res.rows, null, 2));
  await client.end();
}

check().catch(console.error);
