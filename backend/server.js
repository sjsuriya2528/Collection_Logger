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
const db = require('./db');
require('dotenv').config();

const app = express();

// Cloudinary Config
cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
  api_key: process.env.CLOUDINARY_API_KEY,
  api_secret: process.env.CLOUDINARY_API_SECRET
});

// Multer Config (Using memory storage for cloud uploads)
const storage = multer.diskStorage({}); // Temp storage for upload
const upload = multer({ 
  storage,
  limits: { fileSize: 10 * 1024 * 1024 } 
});

app.use(cors());
app.use(express.json());

// 5. ADD DEBUG LOGGING
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  if (req.method === 'POST') {
    const bodyCopy = { ...req.body };
    if (bodyCopy.password) bodyCopy.password = '******';
    console.log('Body:', bodyCopy);
  }
  next();
});

// 1. VERIFY ROUTE DEFINITIONS (Health Checks)
app.get('/', (req, res) => res.send('ACM Collection Logger Backend is running'));
app.get('/api/auth/signup', (req, res) => res.send('Signup endpoint is alive. Use POST to register.'));

app.use('/uploads', express.static('uploads'));

const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET;

// Email Transporter Setup
const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: parseInt(process.env.SMTP_PORT),
  secure: false, 
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS
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
        payment_proof TEXT
      )
    `);
    
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
  const { name, email, password, role } = req.body;
  console.log(`Signup attempt for email: ${email}`);
  try {
    const existing = await db.query('SELECT id FROM users WHERE email = $1', [email]);
    console.log(`Search result for ${email}: ${existing.rows.length} rows found`);
    if (existing.rows.length > 0) {
      return res.status(400).json({ message: 'Email already registered' });
    }

    const hashedPassword = await bcrypt.hash(password, 10);
    const result = await db.query(
      'INSERT INTO users (name, email, password_hash, role) VALUES ($1, $2, $3, $4) RETURNING id, name, role',
      [name, email, hashedPassword, role]
    );
    
    const user = result.rows[0];
    const token = jwt.sign({ id: user.id, role: user.role }, JWT_SECRET);
    
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
      const token = jwt.sign({ id: user.id, role: user.role }, JWT_SECRET);
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
      console.log(`OTP sent successfully to ${email}`);
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
    res.json({ message: 'OTP verified' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/auth/reset-password', async (req, res) => {
  const { email, otp, newPassword } = req.body;
  try {
    // Re-verify OTP for security
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
    const expiry = new Date(Date.now() + 10 * 60000); // 10 mins

    await db.query('UPDATE users SET otp_code = $1, otp_expiry = $2 WHERE id = $3', [otp, expiry, req.user.id]);

    try {
      await transporter.sendMail({
        from: process.env.SMTP_USER,
        to: email,
        subject: 'Password Change Verification',
        text: `Your OTP for changing your password is: ${otp}. It expires in 10 minutes.`
      });
      console.log(`Password change OTP sent to ${email}`);
    } catch (mailErr) {
      console.error('Nodemailer Error:', mailErr);
      return res.status(500).json({ message: 'Error sending email', details: mailErr.message });
    }

    res.json({ message: 'OTP sent to your registered email' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/auth/change-password', authenticateToken, async (req, res) => {
  const { otp, newPassword } = req.body;
  try {
    // Verify OTP for this specific logged-in user
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

// Helper to upload to Cloudinary
const uploadToCloudinary = async (filePath, folder) => {
  try {
    const result = await cloudinary.uploader.upload(filePath, {
      folder: folder,
      resource_type: 'auto'
    });
    // Remove local temp file
    if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
    return result.secure_url;
  } catch (err) {
    console.error('Cloudinary Upload Error:', err);
    return null;
  }
};

// --- COLLECTION ENDPOINTS (Employee) ---

app.post('/api/collections', authenticateToken, upload.fields([
  { name: 'billProof', maxCount: 1 },
  { name: 'paymentProof', maxCount: 1 }
]), async (req, res) => {
  const { id, bill_no, shop_name, amount, payment_mode, date, status } = req.body;
  
  let billProofUrl = null;
  let paymentProofUrl = null;

  if (req.files && req.files['billProof']) {
    billProofUrl = await uploadToCloudinary(req.files['billProof'][0].path, 'bills');
  }
  if (req.files && req.files['paymentProof']) {
    paymentProofUrl = await uploadToCloudinary(req.files['paymentProof'][0].path, 'payments');
  }

  try {
    // Check if ID already exists (prevent duplicates)
    const existing = await db.query('SELECT id FROM collections WHERE id = $1', [id]);
    if (existing.rows.length > 0) {
      return res.status(200).json({ message: 'Already synced' });
    }

    await db.query(
      'INSERT INTO collections (id, employee_id, bill_no, shop_name, amount, payment_mode, date, status, bill_proof, payment_proof) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)',
      [id, req.user.id, bill_no, shop_name, amount, payment_mode, date, status, billProofUrl, paymentProofUrl]
    );
    res.status(201).json({ message: 'Collection synced' });
  } catch (err) {
    console.error('Sync Error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/collections/mine', authenticateToken, async (req, res) => {
  try {
    const result = await db.query(
      'SELECT * FROM collections WHERE employee_id = $1 ORDER BY date DESC',
      [req.user.id]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// --- ADMIN ENDPOINTS ---

app.get('/api/employees', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ message: 'Admin only' });
  
  try {
    const result = await db.query(`
      SELECT u.id as user_id, u.name, 
      COALESCE(SUM(c.amount), 0) as today_total
      FROM users u
      LEFT JOIN collections c ON u.id = c.employee_id 
      AND (c.date AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata')::date = (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Kolkata')::date
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
        WHERE (date AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata')::date = (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Kolkata')::date
      `);
      
      const modeBreakdown = await db.query(`
        SELECT payment_mode, SUM(amount) as total 
        FROM collections 
        WHERE (date AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata')::date = (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Kolkata')::date
        GROUP BY payment_mode
      `);
      
      res.json({
        today_total: todayTotal.rows[0].total,
        breakdown: modeBreakdown.rows
      });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
});

// Get all collections for a specific employee (Admin only)
app.get('/api/collections/employee/:id', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ message: 'Admin only' });
  
  const { id } = req.params;
  try {
    const result = await db.query(
      'SELECT * FROM collections WHERE employee_id = $1 ORDER BY date DESC',
      [id]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Update a collection record
app.put('/api/collections/:id', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ message: 'Admin only' });
  
  const { id } = req.params;
  const { bill_no, shop_name, amount, payment_mode } = req.body;
  try {
    const result = await db.query(
      'UPDATE collections SET bill_no = $1, shop_name = $2, amount = $3, payment_mode = $4 WHERE id = $5 RETURNING *',
      [bill_no, shop_name, amount, payment_mode, id]
    );
    if (result.rows.length === 0) return res.status(404).json({ message: 'Not found' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Delete a collection record (Admin Only)
app.delete('/api/collections/:id', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ message: 'Admin only' });
  
  const { id } = req.params;
  try {
    const result = await db.query('DELETE FROM collections WHERE id = $1 RETURNING *', [id]);
    if (result.rows.length === 0) return res.status(404).json({ message: 'Record not found' });
    res.json({ message: 'Record deleted successfully' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
});
