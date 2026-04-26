process.env.TZ = 'Asia/Kolkata';
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const nodemailer = require('nodemailer');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const cloudinary = require('cloudinary').v2;
require('dotenv').config({ path: path.join(__dirname, '.env') });
const db = require('./db');

const app = express();

cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
  api_key: process.env.CLOUDINARY_API_KEY,
  api_secret: process.env.CLOUDINARY_API_SECRET
});

// Firebase Admin Setup
let serviceAccount = null;
const serviceAccountPath = path.join(__dirname, 'firebase-service-account.json');

if (process.env.FIREBASE_SERVICE_ACCOUNT) {
  try {
    serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    console.log('✅ Firebase Service Account loaded from Env Var');
  } catch (err) {
    console.error('❌ Failed to parse FIREBASE_SERVICE_ACCOUNT env var:', err);
  }
} else if (fs.existsSync(serviceAccountPath)) {
  serviceAccount = require(serviceAccountPath);
  console.log('✅ Firebase Service Account loaded from file');
}

if (serviceAccount) {
  try {
    const admin = require('firebase-admin');
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
    console.log('✅ Firebase Admin Initialized');
    app.locals.fcmAdmin = admin;
  } catch (err) {
    console.error('❌ Firebase Init Error:', err);
  }
} else {
  console.log('⚠️ Firebase service account not found (Env or File). Notifications will be skipped.');
}

// Notification Helper
const sendAdminNotification = async (title, body) => {
  const admin = app.locals.fcmAdmin;
  if (!admin) return;

  try {
    // Get all admin tokens
    const tokensResult = await db.query(`
      SELECT t.token 
      FROM fcm_tokens t
      JOIN users u ON t.user_id = u.id
      WHERE u.role = 'admin'
    `);
    
    const tokens = tokensResult.rows.map(r => r.token);
    if (tokens.length === 0) return;

    const message = {
      notification: { title, body },
      tokens: tokens,
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`Successfully sent ${response.successCount} notifications`);
  } catch (err) {
    console.error('Error sending push notification:', err);
  }
};

// Cloudinary Upload Helper
const uploadToCloudinary = async (filePath, folder = 'collections') => {
  try {
    const result = await cloudinary.uploader.upload(filePath, {
      folder,
      resource_type: 'auto'
    });
    // Remove local file after upload
    if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
    return result.secure_url;
  } catch (error) {
    console.error('Cloudinary Upload Error:', error);
    if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
    return null;
  }
};

// Cloudinary Delete Helper
const deleteCloudinaryFile = async (url) => {
  if (!url || !url.includes('cloudinary.com')) {
    // Handle local file cleanup if necessary
    if (url && url.startsWith('/uploads/')) {
      const localPath = path.join(__dirname, url);
      if (fs.existsSync(localPath)) fs.unlinkSync(localPath);
    }
    return;
  }
  try {
    const parts = url.split('/');
    const lastPart = parts.pop(); 
    const folder = parts.pop(); 
    const publicId = `${folder}/${lastPart.split('.')[0]}`;
    await cloudinary.uploader.destroy(publicId);
    console.log(`Cloudinary file deleted: ${publicId}`);
  } catch (err) {
    console.error('Cloudinary Delete Error:', err);
  }
};

// Multer Config
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const uploadPath = 'D:/Projects/Collection_Logger/backend/uploads';
    if (!fs.existsSync(uploadPath)) fs.mkdirSync(uploadPath, { recursive: true });
    cb(null, uploadPath);
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, file.fieldname + '-' + uniqueSuffix + path.extname(file.originalname));
  }
});
const upload = multer({ 
  storage,
  limits: { fileSize: 10 * 1024 * 1024 } 
});

app.use(cors());
app.use(express.json());

// DEBUG LOGGING
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  if (req.method === 'POST') {
    const bodyCopy = { ...req.body };
    if (bodyCopy.password) bodyCopy.password = '******';
    console.log('Body:', bodyCopy);
  }
  next();
});

// HEALTH CHECKS
app.get('/', (req, res) => res.send('ACM Collection Logger Backend is running'));
app.get('/api/auth/signup', (req, res) => res.send('Signup endpoint is alive. Use POST to register.'));

app.use('/uploads', express.static('D:/Projects/Collection_Logger/backend/uploads'));

const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET;

// Email Transporter Setup
const smtpPort = parseInt(process.env.SMTP_PORT) || 587;
const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: smtpPort,
  secure: smtpPort === 465, // true for 465, false for other ports
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS
  },
  tls: {
    rejectUnauthorized: false // Helps with some cloud hosting certificate issues
  }
});

// Verify Transporter
transporter.verify((error, success) => {
  if (error) {
    console.error('SMTP Connection Error:', error);
  } else {
    console.log('SMTP Server is ready to take our messages');
  }
});

// Migration: Ensure necessary tables and columns exist
const ensureColumns = async () => {
  try {
    console.log('4. DATABASE CONNECTION CHECK: Connecting to PostgreSQL...');
    const dbTest = await db.query('SELECT NOW()');
    console.log('✅ Connected to DB at:', dbTest.rows[0].now);

    // Set the database session to Indian Standard Time
    await db.query("SET TIME ZONE 'Asia/Kolkata'");
    
    // Create Users table
    await db.query(`
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'employee',
        otp_code TEXT,
        otp_expiry TIMESTAMP
      )
    `);

    // Create Collections table
    await db.query(`
      CREATE TABLE IF NOT EXISTS collections (
        id TEXT PRIMARY KEY,
        employee_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
        bill_no TEXT NOT NULL,
        shop_name TEXT NOT NULL,
        amount DECIMAL NOT NULL,
        payment_mode TEXT NOT NULL,
        date TIMESTAMP NOT NULL,
        status TEXT DEFAULT 'partial',
        bill_proof TEXT,
        payment_proof TEXT,
        cash_amount DECIMAL DEFAULT 0,
        upi_amount DECIMAL DEFAULT 0,
        group_id TEXT
      )
    `);

    // Create FCM Tokens table
    await db.query(`
      CREATE TABLE IF NOT EXISTS fcm_tokens (
        id SERIAL PRIMARY KEY,
        user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
        token TEXT UNIQUE NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);
    
    // Safe Migrations
    await db.query('ALTER TABLE collections ADD COLUMN IF NOT EXISTS status TEXT DEFAULT \'partial\'');
    await db.query('ALTER TABLE collections ADD COLUMN IF NOT EXISTS cash_amount DECIMAL DEFAULT 0');
    await db.query('ALTER TABLE collections ADD COLUMN IF NOT EXISTS upi_amount DECIMAL DEFAULT 0');
    await db.query('ALTER TABLE collections ADD COLUMN IF NOT EXISTS group_id TEXT');
    
    console.log('Database schema verified and tables created');
  } catch (err) {
    console.error('Migration Error:', err);
  }
};
ensureColumns();

// Middleware to verify JWT
const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) return res.status(401).json({ message: 'Token required' });

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) return res.status(403).json({ message: 'Invalid token' });
    req.user = user;
    next();
  });
};

// --- AUTH ENDPOINTS ---

app.post('/api/auth/signup', async (req, res) => {
  const { name, email, password, role, admin_secret_code } = req.body;
  
  if (role === 'admin') {
    if (!admin_secret_code || admin_secret_code !== process.env.ADMIN_SECRET_CODE) {
      return res.status(403).json({ message: 'Invalid Admin Secret Code' });
    }
  }

  try {
    const existing = await db.query('SELECT id FROM users WHERE email = $1', [email]);
    if (existing.rows.length > 0) {
      return res.status(400).json({ message: 'Email already registered' });
    }

    const hashedPassword = await bcrypt.hash(password, 10);
    const result = await db.query(
      'INSERT INTO users (name, email, password_hash, role) VALUES ($1, $2, $3, $4) RETURNING id, name, role',
      [name, email, hashedPassword, role]
    );
    
    const user = result.rows[0];
    const token = jwt.sign({ id: user.id, name: user.name, role: role }, JWT_SECRET);
    
    res.status(201).json({
      success: true,
      message: "User created",
      user: {
        id: user.id,
        name: user.name,
        role: user.role
      },
      token: token
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/auth/login', async (req, res) => {
  const { email, password } = req.body;
  try {
    const result = await db.query('SELECT * FROM users WHERE email = $1', [email]);
    const user = result.rows[0];

    if (user && await bcrypt.compare(password, user.password_hash)) {
      const token = jwt.sign({ id: user.id, name: user.name, role: user.role }, JWT_SECRET);
      res.json({
        user_id: user.id,
        name: user.name,
        role: user.role,
        token: token
      });
    } else {
      res.status(401).json({ message: 'Invalid credentials' });
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/auth/forgot-password', async (req, res) => {
  const { email } = req.body;
  try {
    const result = await db.query('SELECT id FROM users WHERE email = $1', [email]);
    if (result.rows.length === 0) return res.status(404).json({ message: 'User not found' });

    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    const expiry = new Date(Date.now() + 10 * 60000); // 10 mins

    await db.query('UPDATE users SET otp_code = $1, otp_expiry = $2 WHERE email = $3', [otp, expiry, email]);

    try {
      await transporter.sendMail({
        from: process.env.SMTP_USER,
        to: email,
        subject: 'Password Reset OTP',
        text: `Your OTP for password reset is: ${otp}. It expires in 10 minutes.`
      });
    } catch (mailErr) {
      console.error('Nodemailer Error:', mailErr);
      return res.status(500).json({ message: 'Error sending email', details: mailErr.message });
    }

    res.json({ message: 'OTP sent to email' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/auth/verify-otp', async (req, res) => {
  const { email, otp } = req.body;
  try {
    const result = await db.query('SELECT * FROM users WHERE email = $1 AND otp_code = $2 AND otp_expiry > NOW()', [email, otp]);
    if (result.rows.length === 0) return res.status(400).json({ message: 'Invalid or expired OTP' });
    res.json({ message: 'OTP verified successfully' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/auth/register-fcm-token', authenticateToken, async (req, res) => {
  const { token } = req.body;
  if (!token) return res.status(400).json({ message: 'Token required' });

  try {
    await db.query(
      'INSERT INTO fcm_tokens (user_id, token) VALUES ($1, $2) ON CONFLICT (token) DO UPDATE SET user_id = $1',
      [req.user.id, token]
    );
    console.log(`[FCM] Registered token for user ${req.user.id}`);
    res.json({ message: 'Token registered' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/auth/reset-password', async (req, res) => {
  const { email, otp, newPassword } = req.body;
  try {
    const result = await db.query('SELECT * FROM users WHERE email = $1 AND otp_code = $2 AND otp_expiry > NOW()', [email, otp]);
    if (result.rows.length === 0) return res.status(400).json({ message: 'Session expired, try again' });

    const hashedPassword = await bcrypt.hash(newPassword, 10);
    await db.query('UPDATE users SET password_hash = $1, otp_code = NULL, otp_expiry = NULL WHERE email = $2', [hashedPassword, email]);
    
    res.json({ message: 'Password reset successful' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/auth/request-change-otp', authenticateToken, async (req, res) => {
  try {
    const result = await db.query('SELECT email FROM users WHERE id = $1', [req.user.id]);
    const email = result.rows[0].email;
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    const expiry = new Date(Date.now() + 10 * 60000); 

    await db.query('UPDATE users SET otp_code = $1, otp_expiry = $2 WHERE id = $3', [otp, expiry, req.user.id]);

    await transporter.sendMail({
      from: process.env.SMTP_USER,
      to: email,
      subject: 'Password Change Verification',
      text: `Your OTP for changing your password is: ${otp}. It expires in 10 minutes.`
    });

    res.json({ message: 'OTP sent to your registered email' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/auth/change-password', authenticateToken, async (req, res) => {
  const { otp, newPassword } = req.body;
  try {
    const result = await db.query(
      'SELECT * FROM users WHERE id = $1 AND otp_code = $2 AND otp_expiry > NOW()', 
      [req.user.id, otp]
    );
    if (result.rows.length === 0) return res.status(400).json({ message: 'Invalid or expired OTP' });

    const hashedNew = await bcrypt.hash(newPassword, 10);
    await db.query(
      'UPDATE users SET password_hash = $1, otp_code = NULL, otp_expiry = NULL WHERE id = $2', 
      [hashedNew, req.user.id]
    );
    res.json({ message: 'Password changed successfully' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// --- COLLECTION ENDPOINTS ---

app.post('/api/collections', authenticateToken, upload.fields([
  { name: 'billProof', maxCount: 1 },
  { name: 'paymentProof', maxCount: 1 }
]), async (req, res) => {
  const { id, bill_no, shop_name, amount, payment_mode, date, status, cash_amount, upi_amount, group_id } = req.body;
  
  let billProofUrl = null;
  let paymentProofUrl = null;

  if (req.files && req.files['billProof']) {
    billProofUrl = await uploadToCloudinary(req.files['billProof'][0].path, 'bills');
  }
  if (req.files && req.files['paymentProof']) {
    paymentProofUrl = await uploadToCloudinary(req.files['paymentProof'][0].path, 'payments');
  }

  try {
    const existing = await db.query('SELECT id FROM collections WHERE id = $1', [id]);
    if (existing.rows.length > 0) return res.status(200).json({ message: 'Already synced' });

    await db.query(
      'INSERT INTO collections (id, employee_id, bill_no, shop_name, amount, payment_mode, date, status, bill_proof, payment_proof, cash_amount, upi_amount, group_id) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)',
      [id, req.user.id, bill_no, shop_name, amount, payment_mode, date, status, billProofUrl, paymentProofUrl, parseFloat(cash_amount || 0), parseFloat(upi_amount || 0), group_id]
    );

    if (!req.user.name) {
      const userRes = await db.query('SELECT name FROM users WHERE id = $1', [req.user.id]);
      if (userRes.rows.length > 0) req.user.name = userRes.rows[0].name;
    }

    sendAdminNotification(
      'New Collection Added',
      `${req.user.name || 'An employee'} added Bill #${bill_no} for ${shop_name} (₹${amount})`
    );

    await db.query(
      'INSERT INTO system_updates (action_type, employee_name, details) VALUES ($1, $2, $3)',
      ['add', req.user.name || 'An employee', `Bill #${bill_no} for ${shop_name} (₹${amount})`]
    );

    res.status(201).json({ message: 'Collection synced', bill_proof: billProofUrl, payment_proof: paymentProofUrl });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/collections/mine', authenticateToken, async (req, res) => {
  try {
    const result = await db.query('SELECT * FROM collections WHERE employee_id = $1 ORDER BY date DESC', [req.user.id]);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ADMIN DASHBOARD
const moment = require('moment-timezone');

app.get('/api/employees', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ message: 'Admin only' });
  try {
    const result = await db.query(`
      SELECT u.id as user_id, u.name, COALESCE(SUM(c.amount), 0) as today_total
      FROM users u
      LEFT JOIN collections c ON u.id = c.employee_id 
        AND c.date::date = CURRENT_DATE
      WHERE u.role = 'employee'
      GROUP BY u.id, u.name
    `);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/admin/dashboard', authenticateToken, async (req, res) => {
    if (req.user.role !== 'admin') return res.status(403).json({ message: 'Admin only' });
    try {
      const todayTotal = await db.query(`
        SELECT COALESCE(SUM(amount), 0) as total 
        FROM collections 
        WHERE date::date = CURRENT_DATE
      `);

      const modeBreakdown = await db.query(`
        SELECT 
          COALESCE(SUM(CASE WHEN payment_mode = 'cash' THEN amount WHEN payment_mode = 'both' THEN cash_amount ELSE 0 END), 0) as cash_total,
          COALESCE(SUM(CASE WHEN payment_mode = 'upi' THEN amount WHEN payment_mode = 'both' THEN upi_amount ELSE 0 END), 0) as upi_total,
          COALESCE(SUM(CASE WHEN payment_mode = 'cheque' THEN amount ELSE 0 END), 0) as cheque_total
        FROM collections 
        WHERE date::date = CURRENT_DATE
      `);

      const latestCollection = await db.query(`
        SELECT c.*, u.name as employee_name
        FROM collections c
        JOIN users u ON c.employee_id = u.id
        WHERE c.date::date = CURRENT_DATE
        ORDER BY c.date DESC
        LIMIT 1
      `);

      const latestUpdate = await db.query(`
        SELECT * FROM system_updates 
        ORDER BY created_at DESC 
        LIMIT 1
      `);

      res.json({
        today_total: todayTotal.rows[0].total,
        breakdown: [
          { payment_mode: 'cash', total: modeBreakdown.rows[0].cash_total },
          { payment_mode: 'upi', total: modeBreakdown.rows[0].upi_total },
          { payment_mode: 'cheque', total: modeBreakdown.rows[0].cheque_total }
        ],
        latest_event: latestUpdate.rows.length > 0 ? latestUpdate.rows[0] : null
      });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
});

app.get('/api/collections/employee/:id', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ message: 'Admin only' });
  try {
    const result = await db.query('SELECT * FROM collections WHERE employee_id = $1 ORDER BY date DESC', [req.params.id]);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.put('/api/collections/:id', authenticateToken, upload.fields([
  { name: 'bill_proof', maxCount: 1 },
  { name: 'payment_proof', maxCount: 1 }
]), async (req, res) => {
  const { id } = req.params;
  const ownerCheck = await db.query('SELECT employee_id, bill_proof, payment_proof FROM collections WHERE id = $1', [id]);
  if (ownerCheck.rows.length === 0) return res.status(404).json({ message: 'Not found' });
  if (req.user.role !== 'admin' && ownerCheck.rows[0].employee_id !== req.user.id) return res.status(403).json({ message: 'Access denied' });
  
  const { bill_no, shop_name, amount, payment_mode, status, cash_amount, upi_amount } = req.body;
  
  try {
    let billProofUrl = req.body.bill_proof !== undefined ? req.body.bill_proof : ownerCheck.rows[0].bill_proof;
    let paymentProofUrl = req.body.payment_proof !== undefined ? req.body.payment_proof : ownerCheck.rows[0].payment_proof;

    if (req.files['bill_proof']) billProofUrl = await uploadToCloudinary(req.files['bill_proof'][0].path, 'bills');
    if (req.files['payment_proof']) paymentProofUrl = await uploadToCloudinary(req.files['payment_proof'][0].path, 'payments');

    if (status !== 'completed') billProofUrl = null;
    if (payment_mode !== 'upi' && payment_mode !== 'both') paymentProofUrl = null;

    const result = await db.query(
      'UPDATE collections SET bill_no = $1, shop_name = $2, amount = $3, payment_mode = $4, status = $5, bill_proof = $6, payment_proof = $7, cash_amount = $8, upi_amount = $9 WHERE id = $10 RETURNING *',
      [bill_no, shop_name, parseFloat(amount), payment_mode, status || 'partial', billProofUrl, paymentProofUrl, parseFloat(cash_amount || 0), parseFloat(upi_amount || 0), id]
    );

    if (!req.user.name) {
      const userRes = await db.query('SELECT name FROM users WHERE id = $1', [req.user.id]);
      if (userRes.rows.length > 0) req.user.name = userRes.rows[0].name;
    }

    sendAdminNotification('Collection Edited', `${req.user.name || 'An employee'} updated Bill #${bill_no} for ${shop_name}`);
    
    await db.query(
      'INSERT INTO system_updates (action_type, employee_name, details) VALUES ($1, $2, $3)',
      ['edit', req.user.name || 'An employee', `Bill #${bill_no} for ${shop_name}`]
    );

    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.delete('/api/collections/:id', authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;
    if (req.user.role !== 'admin') {
      const ownerCheck = await db.query('SELECT employee_id FROM collections WHERE id = $1', [id]);
      if (ownerCheck.rows.length === 0) return res.status(404).json({ message: 'Not found' });
      if (ownerCheck.rows[0].employee_id !== req.user.id) return res.status(403).json({ message: 'Access denied' });
    }
    const result = await db.query('DELETE FROM collections WHERE id = $1 RETURNING *', [id]);
    const deletedRecord = result.rows[0];

    if (deletedRecord.bill_proof) {
      const count = await db.query('SELECT count(*) FROM collections WHERE bill_proof = $1', [deletedRecord.bill_proof]);
      if (parseInt(count.rows[0].count) === 0) await deleteCloudinaryFile(deletedRecord.bill_proof);
    }
    if (deletedRecord.payment_proof) {
      const count = await db.query('SELECT count(*) FROM collections WHERE payment_proof = $1', [deletedRecord.payment_proof]);
      if (parseInt(count.rows[0].count) === 0) await deleteCloudinaryFile(deletedRecord.payment_proof);
    }

    if (!req.user.name) {
      const userRes = await db.query('SELECT name FROM users WHERE id = $1', [req.user.id]);
      if (userRes.rows.length > 0) req.user.name = userRes.rows[0].name;
    }

    sendAdminNotification(
      'Collection Deleted', 
      `${req.user.name || 'An employee'} deleted Bill #${deletedRecord.bill_no} for ${deletedRecord.shop_name}`
    );

    await db.query(
      'INSERT INTO system_updates (action_type, employee_name, details) VALUES ($1, $2, $3)',
      ['delete', req.user.name || 'An employee', `Bill #${deletedRecord.bill_no} for ${deletedRecord.shop_name}`]
    );

    res.json({ message: 'Deleted successfully' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
});
