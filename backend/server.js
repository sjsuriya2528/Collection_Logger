process.env.TZ = 'Asia/Kolkata';
const dns = require('dns');
if (dns.setDefaultResultOrder) {
  dns.setDefaultResultOrder('ipv4first');
}
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
  if (!admin) {
    console.log('[FCM] Skipping notification: Firebase Admin not initialized');
    return;
  }

  try {
    // Get all admin tokens
    const tokensResult = await db.query(`
      SELECT t.token 
      FROM fcm_tokens t
      JOIN users u ON t.user_id = u.id
      WHERE u.role = 'admin'
    `);
    
    const tokens = tokensResult.rows.map(r => r.token);
    console.log(`[FCM] Sending notification to ${tokens.length} admin(s)`);
    if (tokens.length === 0) return;

    const message = {
      notification: { title, body },
      data: {
        title: title,
        body: body,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      tokens: tokens,
      android: {
        priority: 'high',
        notification: {
          channelId: 'admin_alerts',
          priority: 'max',
        }
      }
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`[FCM] Sent to Google: ${response.successCount} success, ${response.failureCount} failure`);
    if (response.failureCount > 0) {
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          console.error(`[FCM] Token ${idx} failed: ${resp.error.message}`);
        }
      });
    }
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
const deleteCloudinaryFile = async (urlStr) => {
  if (!urlStr) return;
  const urls = urlStr.split(',');
  for (const url of urls) {
    if (!url.includes('cloudinary.com')) {
      // Handle local file cleanup if necessary
      if (url && url.startsWith('/uploads/')) {
        const localPath = path.join(__dirname, url);
        if (fs.existsSync(localPath)) fs.unlinkSync(localPath);
      }
      continue;
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
const transporter = nodemailer.createTransport({
  host: 'smtp.gmail.com',
  port: 587,
  secure: false, // Use STARTTLS
  family: 4,     // Force IPv4 only to avoid ENETUNREACH on IPv6
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS
  },
  tls: {
    rejectUnauthorized: false
  },
  connectionTimeout: 10000,
  greetingTimeout: 10000,
  socketTimeout: 10000
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

    // Create System Updates table (For Windows notifications)
    await db.query(`
      CREATE TABLE IF NOT EXISTS system_updates (
        id SERIAL PRIMARY KEY,
        action_type TEXT,
        employee_name TEXT,
        details TEXT,
        created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
      );
    `);

    // Create Shop Balances table
    await db.query(`
      CREATE TABLE IF NOT EXISTS shop_balances (
        id SERIAL PRIMARY KEY,
        shop_name TEXT NOT NULL,
        amount DECIMAL NOT NULL,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);
    
    // Safe Migrations
    await db.query('ALTER TABLE collections ALTER COLUMN bill_no DROP NOT NULL');
    await db.query('ALTER TABLE collections ADD COLUMN IF NOT EXISTS status TEXT DEFAULT \'partial\'');
    await db.query('ALTER TABLE collections ADD COLUMN IF NOT EXISTS cash_amount DECIMAL DEFAULT 0');
    await db.query('ALTER TABLE collections ADD COLUMN IF NOT EXISTS upi_amount DECIMAL DEFAULT 0');
    await db.query('ALTER TABLE collections ADD COLUMN IF NOT EXISTS group_id TEXT');

    // Add performance indexes — critical for fast queries as data grows
    // Without these, every query does a full table scan (very slow!)
    await db.query('CREATE INDEX IF NOT EXISTS idx_collections_date ON collections(date DESC)');
    await db.query('CREATE INDEX IF NOT EXISTS idx_collections_employee_id ON collections(employee_id)');
    await db.query('CREATE INDEX IF NOT EXISTS idx_collections_group_id ON collections(group_id)');
    await db.query('CREATE INDEX IF NOT EXISTS idx_collections_employee_date ON collections(employee_id, date DESC)');
    await db.query('CREATE INDEX IF NOT EXISTS idx_collections_status ON collections(status)');
    
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
        from: `"ACM Agencies Alerts" <${process.env.SMTP_USER}>`,
        to: email,
        subject: 'Password Reset OTP',
        text: `Your OTP for password reset is: ${otp}. It expires in 10 minutes.`
      });
      console.log(`[OTP] Sent reset code to ${email}`);
    } catch (mailErr) {
      console.error('[OTP] Nodemailer Error:', mailErr.message);
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

app.post('/api/auth/logout', authenticateToken, async (req, res) => {
  const { token } = req.body;
  try {
    if (token) {
      await db.query('DELETE FROM fcm_tokens WHERE token = $1 AND user_id = $2', [token, req.user.id]);
      console.log(`[FCM] Unregistered token for user ${req.user.id}`);
    }
    res.json({ message: 'Logged out successfully' });
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
      from: `"ACM Agencies Alerts" <${process.env.SMTP_USER}>`,
      to: email,
      subject: 'Password Change Verification',
      text: `Your OTP for changing your password is: ${otp}. It expires in 10 minutes.`
    });
    console.log(`[OTP] Sent change code to ${email}`);

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

app.post('/api/upload', authenticateToken, upload.single('file'), async (req, res) => {
  if (!req.file) return res.status(400).json({ message: 'No file uploaded' });
  const folder = req.body.type === 'bill' ? 'bills' : 'payments';
  try {
    const url = await uploadToCloudinary(req.file.path, folder);
    res.json({ url });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// --- COLLECTION ENDPOINTS ---

app.post('/api/collections', authenticateToken, upload.fields([
  { name: 'billProof', maxCount: 10 },
  { name: 'paymentProof', maxCount: 1 }
]), async (req, res) => {
  const { id, bill_no, shop_name, amount, payment_mode, date, status, cash_amount, upi_amount, group_id } = req.body;
  
  let billProofUrl = req.body.bill_proof ?? req.body.billProof ?? null;
  let paymentProofUrl = req.body.payment_proof ?? req.body.paymentProof ?? null;

  if (req.files && req.files['billProof']) {
    const urls = [];
    for (const file of req.files['billProof']) {
      const url = await uploadToCloudinary(file.path, 'bills');
      if (url) urls.push(url);
    }
    if (urls.length > 0) {
      billProofUrl = billProofUrl ? `${billProofUrl},${urls.join(',')}` : urls.join(',');
    }
  }
  if (req.files && req.files['paymentProof']) {
    paymentProofUrl = await uploadToCloudinary(req.files['paymentProof'][0].path, 'payments');
  }

  try {
    const existing = await db.query('SELECT * FROM collections WHERE id = $1', [id]);
    
    if (existing.rows.length > 0) {
      const old = existing.rows[0];
      const clean = (val) => (val || '').toString().trim();
      const cleanLower = (val) => clean(val).toLowerCase();

      const hasChanged = 
        clean(old.bill_no) !== clean(bill_no) ||
        clean(old.shop_name) !== clean(shop_name) ||
        parseFloat(old.amount || 0) !== parseFloat(amount || 0) ||
        cleanLower(old.payment_mode) !== cleanLower(payment_mode) ||
        cleanLower(old.status) !== cleanLower(status) ||
        clean(old.bill_proof) !== clean(billProofUrl) ||
        clean(old.payment_proof) !== clean(paymentProofUrl) ||
        parseFloat(old.cash_amount || 0) !== parseFloat(cash_amount || 0) ||
        parseFloat(old.upi_amount || 0) !== parseFloat(upi_amount || 0);

      const finalBillProof = billProofUrl !== null ? billProofUrl : old.bill_proof;
      const finalPaymentProof = paymentProofUrl !== null ? paymentProofUrl : old.payment_proof;

      const oldBills = (old.bill_proof || '').split(',').filter(Boolean);
      const newBills = (finalBillProof || '').split(',').filter(Boolean);
      for (const url of oldBills) {
        if (!newBills.includes(url)) {
          const count = await db.query('SELECT COUNT(*) FROM collections WHERE bill_proof LIKE $1 AND id != $2', [`%${url}%`, id]);
          if (parseInt(count.rows[0].count) === 0) await deleteCloudinaryFile(url);
        }
      }

      if (old.payment_proof && old.payment_proof !== finalPaymentProof) {
        const count = await db.query('SELECT COUNT(*) FROM collections WHERE payment_proof = $1 AND id != $2', [old.payment_proof, id]);
        if (parseInt(count.rows[0].count) === 0) await deleteCloudinaryFile(old.payment_proof);
      }

      const result = await db.query(
        'UPDATE collections SET bill_no = $1, shop_name = $2, amount = $3, payment_mode = $4, status = $5, bill_proof = $6, payment_proof = $7, cash_amount = $8, upi_amount = $9 WHERE id = $10 RETURNING *',
        [bill_no, shop_name, parseFloat(amount || 0), payment_mode, status || 'partial', finalBillProof, finalPaymentProof, parseFloat(cash_amount || 0), parseFloat(upi_amount || 0), id]
      );

      if (hasChanged) {
        if (!req.user.name) {
          const userRes = await db.query('SELECT name FROM users WHERE id = $1', [req.user.id]);
          if (userRes.rows.length > 0) req.user.name = userRes.rows[0].name;
        }
        const billText = bill_no ? `Bill #${bill_no}` : 'No Bill No';
        const modeText = payment_mode ? payment_mode.toString().toUpperCase() : 'N/A';
        sendAdminNotification('Collection Edited (Sync)', `${req.user.name || 'An employee'} updated ${billText} for ${shop_name} (${modeText})`);
        
        await db.query(
          'INSERT INTO system_updates (action_type, employee_name, details) VALUES ($1, $2, $3)',
          ['edit', req.user.name || 'An employee', `${billText} for ${shop_name} (${modeText})`]
        );
      }
      
      return res.status(200).json({ message: 'Collection updated', ...result.rows[0] });
    }

    await db.query(
      'INSERT INTO collections (id, employee_id, bill_no, shop_name, amount, payment_mode, date, status, bill_proof, payment_proof, cash_amount, upi_amount, group_id) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)',
      [id, req.user.id, bill_no, shop_name, parseFloat(amount || 0), payment_mode, date, status, billProofUrl, paymentProofUrl, parseFloat(cash_amount || 0), parseFloat(upi_amount || 0), group_id]
    );

    if (!req.user.name) {
      const userRes = await db.query('SELECT name FROM users WHERE id = $1', [req.user.id]);
      if (userRes.rows.length > 0) req.user.name = userRes.rows[0].name;
    }

    const billText = bill_no ? `Bill #${bill_no}` : 'No Bill No';
    const modeText = payment_mode ? payment_mode.toString().toUpperCase() : 'N/A';
    sendAdminNotification(
      'New Collection Added',
      `${req.user.name || 'An employee'} added ${billText} for ${shop_name} via ${modeText} (₹${amount})`
    );

    await db.query(
      'INSERT INTO system_updates (action_type, employee_name, details) VALUES ($1, $2, $3)',
      ['add', req.user.name || 'An employee', `${billText} for ${shop_name} via ${modeText} (₹${amount})`]
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

app.post('/api/admin/alert', authenticateToken, async (req, res) => {
  const { title, body } = req.body;
  try {
    await sendAdminNotification(title, body);
    res.json({ message: 'Alert sent successfully' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

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

      // Safely fetch latest event (Don't crash if table doesn't exist yet)
      let latestEvent = null;
      try {
        const latestUpdate = await db.query(`
          SELECT * FROM system_updates 
          ORDER BY created_at DESC 
          LIMIT 1
        `);
        if (latestUpdate.rows.length > 0) latestEvent = latestUpdate.rows[0];
      } catch (e) {
        console.warn('System updates table not ready yet');
      }

      res.json({
        today_total: todayTotal.rows[0].total,
        breakdown: [
          { payment_mode: 'cash', total: modeBreakdown.rows[0].cash_total },
          { payment_mode: 'upi', total: modeBreakdown.rows[0].upi_total },
          { payment_mode: 'cheque', total: modeBreakdown.rows[0].cheque_total }
        ],
        latest_event: latestEvent
      });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
});

app.get('/api/admin/collections', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ message: 'Admin only' });
  try {
    const { startDate, endDate } = req.query;
    let query;
    let params = [];

    if (startDate && endDate) {
      // Filter by date range at DB level — much faster than fetching all and filtering in app
      query = `
        SELECT c.*, u.name as employee_name
        FROM collections c
        JOIN users u ON c.employee_id = u.id
        WHERE c.date >= $1::date AND c.date < ($2::date + interval '1 day')
        ORDER BY c.date DESC
      `;
      params = [startDate, endDate];
    } else {
      // No date range — return last 30 days by default to avoid massive payloads
      query = `
        SELECT c.*, u.name as employee_name
        FROM collections c
        JOIN users u ON c.employee_id = u.id
        WHERE c.date >= NOW() - interval '30 days'
        ORDER BY c.date DESC
      `;
    }

    const result = await db.query(query, params);
    res.json(result.rows);
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
  { name: 'bill_proof', maxCount: 10 },
  { name: 'payment_proof', maxCount: 1 }
]), async (req, res) => {
  const { id } = req.params;
  const ownerCheck = await db.query('SELECT employee_id, bill_proof, payment_proof FROM collections WHERE id = $1', [id]);
  if (ownerCheck.rows.length === 0) return res.status(404).json({ message: 'Not found' });
  if (req.user.role !== 'admin' && ownerCheck.rows[0].employee_id !== req.user.id) return res.status(403).json({ message: 'Access denied' });
  
  const { bill_no, shop_name, amount, payment_mode, status, cash_amount, upi_amount } = req.body;
  
  try {
    let billProofUrl = req.body.billProof ?? req.body.bill_proof;
    if (billProofUrl === undefined || billProofUrl === null) {
      billProofUrl = ownerCheck.rows[0].bill_proof;
    }
    
    let paymentProofUrl = req.body.paymentProof ?? req.body.payment_proof;
    if (paymentProofUrl === undefined || paymentProofUrl === null) {
      paymentProofUrl = ownerCheck.rows[0].payment_proof;
    }

    if (req.files && req.files['bill_proof']) {
      const urls = [];
      for (const file of req.files['bill_proof']) {
        const url = await uploadToCloudinary(file.path, 'bills');
        if (url) urls.push(url);
      }
      if (urls.length > 0) {
        billProofUrl = billProofUrl ? `${billProofUrl},${urls.join(',')}` : urls.join(',');
      }
    }
    if (req.files && req.files['payment_proof']) {
      paymentProofUrl = await uploadToCloudinary(req.files['payment_proof'][0].path, 'payments');
    }

    // Remove restrictions that were wiping proofs based on status/mode
    // billProofUrl and paymentProofUrl should be kept if provided by the client

    // Robust Change Detection: Compare old vs new (Case-insensitive for status and mode)
    const old = ownerCheck.rows[0];
    const clean = (val) => (val || '').toString().trim();
    const cleanLower = (val) => clean(val).toLowerCase();

    const hasChanged = 
      clean(old.bill_no) !== clean(bill_no) ||
      clean(old.shop_name) !== clean(shop_name) ||
      parseFloat(old.amount || 0) !== parseFloat(amount || 0) ||
      cleanLower(old.payment_mode) !== cleanLower(payment_mode) ||
      cleanLower(old.status) !== cleanLower(status) ||
      clean(old.bill_proof) !== clean(billProofUrl) ||
      clean(old.payment_proof) !== clean(paymentProofUrl) ||
      parseFloat(old.cash_amount || 0) !== parseFloat(cash_amount || 0) ||
      parseFloat(old.upi_amount || 0) !== parseFloat(upi_amount || 0);

    const oldBills = (old.bill_proof || '').split(',').filter(Boolean);
    const newBills = (billProofUrl || '').split(',').filter(Boolean);
    for (const url of oldBills) {
      if (!newBills.includes(url)) {
        const count = await db.query('SELECT COUNT(*) FROM collections WHERE bill_proof LIKE $1 AND id != $2', [`%${url}%`, id]);
        if (parseInt(count.rows[0].count) === 0) await deleteCloudinaryFile(url);
      }
    }

    if (old.payment_proof && old.payment_proof !== paymentProofUrl) {
      const count = await db.query('SELECT COUNT(*) FROM collections WHERE payment_proof = $1 AND id != $2', [old.payment_proof, id]);
      if (parseInt(count.rows[0].count) === 0) await deleteCloudinaryFile(old.payment_proof);
    }

    const result = await db.query(
      'UPDATE collections SET bill_no = $1, shop_name = $2, amount = $3, payment_mode = $4, status = $5, bill_proof = $6, payment_proof = $7, cash_amount = $8, upi_amount = $9 WHERE id = $10 RETURNING *',
      [bill_no, shop_name, parseFloat(amount), payment_mode, status || 'partial', billProofUrl, paymentProofUrl, parseFloat(cash_amount || 0), parseFloat(upi_amount || 0), id]
    );

    if (hasChanged) {
      if (!req.user.name) {
        const userRes = await db.query('SELECT name FROM users WHERE id = $1', [req.user.id]);
        if (userRes.rows.length > 0) req.user.name = userRes.rows[0].name;
      }

      const billText = bill_no ? `Bill #${bill_no}` : 'No Bill No';
      const modeText = payment_mode ? payment_mode.toString().toUpperCase() : 'N/A';
      sendAdminNotification('Collection Edited', `${req.user.name || 'An employee'} updated ${billText} for ${shop_name} (${modeText})`);
      
      await db.query(
        'INSERT INTO system_updates (action_type, employee_name, details) VALUES ($1, $2, $3)',
        ['edit', req.user.name || 'An employee', `${billText} for ${shop_name} (${modeText})`]
      );
    }

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
      const urls = deletedRecord.bill_proof.split(',').filter(Boolean);
      for (const url of urls) {
        const count = await db.query('SELECT count(*) FROM collections WHERE bill_proof LIKE $1 AND id != $2', [`%${url}%`, id]);
        if (parseInt(count.rows[0].count) === 0) await deleteCloudinaryFile(url);
      }
    }
    if (deletedRecord.payment_proof) {
      const count = await db.query('SELECT count(*) FROM collections WHERE payment_proof = $1 AND id != $2', [deletedRecord.payment_proof, id]);
      if (parseInt(count.rows[0].count) === 0) await deleteCloudinaryFile(deletedRecord.payment_proof);
    }

    if (!req.user.name) {
      const userRes = await db.query('SELECT name FROM users WHERE id = $1', [req.user.id]);
      if (userRes.rows.length > 0) req.user.name = userRes.rows[0].name;
    }

    const billText = deletedRecord.bill_no ? `Bill #${deletedRecord.bill_no}` : 'No Bill No';
    sendAdminNotification(
      'Collection Deleted', 
      `${req.user.name || 'An employee'} deleted ${billText} for ${deletedRecord.shop_name}`
    );

    await db.query(
      'INSERT INTO system_updates (action_type, employee_name, details) VALUES ($1, $2, $3)',
      ['delete', req.user.name || 'An employee', `${billText} for ${deletedRecord.shop_name}`]
    );

    res.json({ message: 'Deleted successfully' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// --- SHOP BALANCES ENDPOINTS ---

app.get('/api/shop-balances', authenticateToken, async (req, res) => {
  try {
    const result = await db.query('SELECT * FROM shop_balances ORDER BY shop_name ASC');
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/shop-balances/bulk', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ message: 'Admin only' });
  const { balances } = req.body;
  if (!Array.isArray(balances)) return res.status(400).json({ message: 'Invalid format' });
  
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    await client.query('TRUNCATE TABLE shop_balances RESTART IDENTITY');
    
    for (const balance of balances) {
      if (balance.shop_name && balance.amount !== undefined) {
        await client.query(
          'INSERT INTO shop_balances (shop_name, amount) VALUES ($1, $2)',
          [balance.shop_name, parseFloat(balance.amount)]
        );
      }
    }
    
    await client.query('COMMIT');
    res.json({ message: 'Shop balances updated successfully' });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ error: err.message });
  } finally {
    client.release();
  }
});

// --- HEALTH CHECK ---

// Simple health check endpoint
app.get('/api/ping', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
});
