const db = require('../backend/db');
async function check() {
  try {
    const res = await db.query("SELECT id, name FROM users WHERE name LIKE '%Sankara%'");
    console.log(JSON.stringify(res.rows, null, 2));
    process.exit(0);
  } catch (e) {
    console.error(e);
    process.exit(1);
  }
}
check();
