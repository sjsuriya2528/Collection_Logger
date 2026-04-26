const db = require('../backend/db');
async function check() {
  try {
    const res = await db.query('SELECT id, employee_id, bill_no, date, amount FROM collections ORDER BY date DESC LIMIT 10');
    console.log(JSON.stringify(res.rows, null, 2));
    process.exit(0);
  } catch (e) {
    console.error(e);
    process.exit(1);
  }
}
check();
