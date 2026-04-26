const db = require('../backend/db');
async function check() {
  try {
    const res = await db.query("SELECT count(*) FROM collections");
    console.log(JSON.stringify(res.rows, null, 2));
    process.exit(0);
  } catch (e) {
    console.error(e);
    process.exit(1);
  }
}
check();
