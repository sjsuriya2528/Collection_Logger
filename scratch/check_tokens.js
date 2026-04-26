const db = require('../backend/db');
async function check() {
  try {
    const res = await db.query("SELECT t.user_id, u.name, u.role, t.token FROM fcm_tokens t JOIN users u ON t.user_id = u.id");
    console.log(JSON.stringify(res.rows, null, 2));
    process.exit(0);
  } catch (e) {
    console.error(e);
    process.exit(1);
  }
}
check();
