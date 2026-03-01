const path = require('path');
const { randomUUID } = require('crypto');
const { promises: fs } = require('fs');

const cors = require('cors');
const dotenv = require('dotenv');
const express = require('express');
const { Resend } = require('resend');

dotenv.config();

const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || '0.0.0.0';
const REPORT_LIMIT_PER_DAY = Number(process.env.REPORT_LIMIT_PER_DAY || 3);
const REPORT_WINDOW_MS = 24 * 60 * 60 * 1000;
const MAX_STORED_REPORTS = Number(process.env.MAX_STORED_REPORTS || 2000);
const MIN_MESSAGE_LENGTH = 5;
const MAX_MESSAGE_LENGTH = 2000;
const RESEND_API_KEY = process.env.RESEND_API_KEY || '';
const RESEND_FROM = process.env.RESEND_FROM || 'WorkyDay <hello@workyday.com>';
const REPORT_TO_EMAIL =
  process.env.REPORT_TO_EMAIL || 'miquelmassomoreno@gmail.com';
const STORAGE_FILE = path.resolve(
  process.env.REPORT_STORAGE_FILE ||
    path.join(__dirname, 'data', 'report-store.json'),
);

const configuredOrigins = (process.env.REPORT_BACKEND_ALLOWED_ORIGINS || '')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);

const app = express();
const resend = RESEND_API_KEY ? new Resend(RESEND_API_KEY) : null;

let store = {
  reports: [],
  limits: {},
};

let writeQueue = Promise.resolve();

const isOriginAllowed = (origin) =>
  !origin ||
  origin.startsWith('http://localhost:') ||
  origin.startsWith('http://127.0.0.1:') ||
  origin.startsWith('https://localhost:') ||
  configuredOrigins.includes(origin);

const escapeHtml = (value) =>
  String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');

const getClientIp = (req) => {
  const forwarded = req.headers['x-forwarded-for'];
  if (typeof forwarded === 'string' && forwarded.trim()) {
    return forwarded.split(',')[0].trim();
  }

  return (
    req.ip ||
    req.socket?.remoteAddress ||
    req.connection?.remoteAddress ||
    'unknown'
  );
};

const queuePersistStore = async () => {
  const snapshot = JSON.stringify(store, null, 2);
  writeQueue = writeQueue
    .catch(() => {})
    .then(async () => {
      await fs.mkdir(path.dirname(STORAGE_FILE), { recursive: true });
      await fs.writeFile(STORAGE_FILE, snapshot, 'utf8');
    });

  await writeQueue;
};

const loadStore = async () => {
  try {
    const raw = await fs.readFile(STORAGE_FILE, 'utf8');
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === 'object') {
      store = {
        reports: Array.isArray(parsed.reports) ? parsed.reports : [],
        limits:
          parsed.limits && typeof parsed.limits === 'object' ? parsed.limits : {},
      };
    }
  } catch (err) {
    if (err.code !== 'ENOENT') {
      throw err;
    }

    await queuePersistStore();
  }
};

const allowCors = cors({
  origin(origin, callback) {
    callback(null, isOriginAllowed(origin));
  },
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type'],
});

app.use(allowCors);
app.options('*', allowCors);
app.use((req, res, next) => {
  const origin = req.headers.origin;
  if (origin && !isOriginAllowed(origin)) {
    res.status(403).json({
      success: false,
      error: 'Origin not allowed',
    });
    return;
  }

  next();
});
app.use(express.json({ limit: '20kb' }));

app.get('/health', (_req, res) => {
  res.status(200).json({
    success: true,
    status: 'ok',
  });
});

app.post('/send-report', async (req, res) => {
  if (!resend) {
    res.status(500).json({
      success: false,
      error: 'Report service is not configured',
    });
    return;
  }

  const body = req.body && typeof req.body === 'object' ? req.body : {};
  const userId = typeof body.userId === 'string' ? body.userId.trim() : '';
  const message = typeof body.message === 'string' ? body.message.trim() : '';
  const platform =
    typeof body.platform === 'string' ? body.platform.trim() : '';
  const appVersion =
    typeof body.appVersion === 'string' ? body.appVersion.trim() : '';

  if (!userId || !message) {
    res.status(400).json({
      success: false,
      error: 'userId and message are required',
    });
    return;
  }

  if (message.length < MIN_MESSAGE_LENGTH || message.length > MAX_MESSAGE_LENGTH) {
    res.status(400).json({
      success: false,
      error: `message must be between ${MIN_MESSAGE_LENGTH} and ${MAX_MESSAGE_LENGTH} characters`,
    });
    return;
  }

  const now = Date.now();
  const limitEntry = store.limits[userId];
  let count = 1;
  let windowStart = now;

  if (limitEntry && typeof limitEntry === 'object') {
    const savedWindowStart = Number(limitEntry.windowStart || 0);
    const savedCount = Number(limitEntry.count || 0);
    const withinWindow =
      savedWindowStart > 0 && now - savedWindowStart <= REPORT_WINDOW_MS;

    if (withinWindow) {
      if (savedCount >= REPORT_LIMIT_PER_DAY) {
        res.status(429).json({
          success: false,
          error: 'Limit reached',
        });
        return;
      }

      windowStart = savedWindowStart;
      count = savedCount + 1;
    }
  }

  const createdAt = new Date(now).toISOString();
  const report = {
    id: randomUUID(),
    userId,
    message,
    createdAt,
    ip: getClientIp(req),
    ...(platform ? { platform } : {}),
    ...(appVersion ? { appVersion } : {}),
  };

  store.limits[userId] = {
    windowStart,
    count,
  };
  store.reports.push(report);
  if (store.reports.length > MAX_STORED_REPORTS) {
    store.reports = store.reports.slice(-MAX_STORED_REPORTS);
  }

  try {
    await queuePersistStore();
  } catch (err) {
    console.error('Failed to persist report store', err);
    res.status(500).json({
      success: false,
      error: 'Could not save report',
    });
    return;
  }

  try {
    const escapedMessage = escapeHtml(message).replace(/\n/g, '<br>');

    const emailResult = await resend.emails.send({
      from: RESEND_FROM,
      to: REPORT_TO_EMAIL,
      subject: 'Nou report des de WorkyDay',
      html: `
        <h2>Nou report des de WorkyDay</h2>
        <p><strong>UserId:</strong> ${escapeHtml(userId)}</p>
        <p><strong>Data/hora:</strong> ${escapeHtml(createdAt)}</p>
        <p><strong>IP:</strong> ${escapeHtml(report.ip)}</p>
        ${
          platform
            ? `<p><strong>Platform:</strong> ${escapeHtml(platform)}</p>`
            : ''
        }
        ${
          appVersion
            ? `<p><strong>App version:</strong> ${escapeHtml(appVersion)}</p>`
            : ''
        }
        <hr>
        <p>${escapedMessage}</p>
      `,
    });

    if (emailResult && emailResult.error) {
      throw new Error(emailResult.error.message || 'Resend email failed');
    }
  } catch (err) {
    console.error('Report saved but email send failed', {
      message: err.message,
      reportId: report.id,
      userId,
    });
    res.status(500).json({
      success: false,
      error: 'Report saved, but email notification failed',
    });
    return;
  }

  res.status(200).json({
    success: true,
    reportId: report.id,
  });
});

loadStore()
  .then(() => {
    app.listen(PORT, HOST, () => {
      console.log(`WorkyDay report backend listening on http://${HOST}:${PORT}`);
    });
  })
  .catch((err) => {
    console.error('Failed to start report backend', err);
    process.exit(1);
  });
