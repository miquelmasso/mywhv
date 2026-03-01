const functions = require('firebase-functions');
const admin = require('firebase-admin');
const fetch = require('node-fetch');
const cheerio = require('cheerio');
const { Resend } = require('resend');

admin.initializeApp();

const REGION = 'australia-southeast1';
const REPORT_LIMIT_PER_DAY = 3;
const REPORT_WINDOW_MS = 24 * 60 * 60 * 1000;
const MIN_REPORT_MESSAGE_LENGTH = 5;
const MAX_REPORT_MESSAGE_LENGTH = 2000;

class RateLimitError extends Error {
  constructor(message) {
    super(message);
    this.name = 'RateLimitError';
  }
}

const uniquePush = (set, value) => {
  if (!value) return;
  const trimmed = value.trim();
  if (trimmed) set.add(trimmed);
};

const normalizePhone = (raw) =>
  raw.replace(/[\s().-]/g, '').replace(/^00/, '+').trim();

const isLikelyPhone = (raw) => {
  const digits = raw.replace(/[^\d+]/g, '');
  return digits.length >= 8 && /\d{3,}/.test(digits);
};

const escapeHtml = (value) =>
  value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');

const isAllowedOrigin = (origin) =>
  !origin ||
  origin.startsWith('http://localhost:') ||
  origin.startsWith('http://127.0.0.1:') ||
  origin.startsWith('https://localhost:');

const setCorsHeaders = (req, res) => {
  const origin = req.get('Origin') || '';
  if (!origin) {
    // Native Flutter clients typically omit Origin.
    res.set('Access-Control-Allow-Origin', '*');
  } else if (isAllowedOrigin(origin)) {
    res.set('Access-Control-Allow-Origin', origin);
  }
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Vary', 'Origin');
};

exports.extractContactsFromUrl = functions
  .region(REGION)
  .https.onCall(async (data, context) => {
    const url = typeof data?.url === 'string' ? data.url.trim() : '';
    if (!url) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Cal proporcionar una URL',
      );
    }

    try {
      // eslint-disable-next-line no-new
      new URL(url);
    } catch (err) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'URL no vàlida',
      );
    }

    functions.logger.info('extractContactsFromUrl fetching', { url });

    let html;
    try {
      const res = await fetch(url, { redirect: 'follow' });
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }
      html = await res.text();
    } catch (err) {
      functions.logger.error('Error fetching URL', { url, err: err.message });
      throw new functions.https.HttpsError(
        'unavailable',
        'No s\'ha pogut descarregar el contingut',
      );
    }

    const emails = new Set();
    const phones = new Set();
    let instagram = null;
    let facebook = null;

    const $ = cheerio.load(html);

    $('a[href^="mailto:"]').each((_, el) => {
      const val = $(el).attr('href')?.replace(/^mailto:/i, '');
      uniquePush(emails, val);
    });

    $('a[href^="tel:"]').each((_, el) => {
      const val = $(el).attr('href')?.replace(/^tel:/i, '');
      if (val && isLikelyPhone(val)) {
        uniquePush(phones, normalizePhone(val));
      }
    });

    const parseEntity = (entity) => {
      if (!entity || typeof entity !== 'object') return;
      if (entity.email) uniquePush(emails, entity.email);
      if (entity.telephone && isLikelyPhone(entity.telephone)) {
        uniquePush(phones, normalizePhone(entity.telephone));
      }
      if (Array.isArray(entity.sameAs)) {
        entity.sameAs.forEach((link) => {
          if (typeof link !== 'string') return;
          if (!instagram && link.includes('instagram.com')) instagram = link;
          if (
            !facebook &&
            (link.includes('facebook.com') || link.includes('fb.me'))
          ) {
            facebook = link;
          }
        });
      }
    };

    $('script[type="application/ld+json"]').each((_, el) => {
      const jsonText = $(el).contents().text();
      try {
        const parsed = JSON.parse(jsonText);
        if (Array.isArray(parsed)) {
          parsed.forEach(parseEntity);
        } else {
          parseEntity(parsed);
        }
      } catch (err) {
        // ignore malformed JSON-LD
      }
    });

    $('a[href]').each((_, el) => {
      const href = $(el).attr('href') || '';
      if (!instagram && href.includes('instagram.com')) {
        instagram = href;
      }
      if (!facebook && (href.includes('facebook.com') || href.includes('fb.me'))) {
        facebook = href;
      }
    });

    const emailRegex =
      /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi;
    const phoneRegex =
      /(?:\+\d{1,3}[\s.-]?)?(?:\(?\d{2,4}\)?[\s.-]?)?\d{3,4}[\s.-]?\d{3,4}/g;

    (html.match(emailRegex) || []).forEach((m) => uniquePush(emails, m));
    (html.match(phoneRegex) || []).forEach((m) => {
      if (isLikelyPhone(m)) uniquePush(phones, normalizePhone(m));
    });

    return {
      emails: Array.from(emails),
      phones: Array.from(phones),
      instagram,
      facebook,
    };
  });

exports.sendReport = functions
  .region(REGION)
  .runWith({ secrets: ['re_iW6ugcGv_GncJPSmj2CNfTcumkLvuyjsS'] })
  .https.onRequest(async (req, res) => {
    setCorsHeaders(req, res);

    const origin = req.get('Origin') || '';
    if (origin && !isAllowedOrigin(origin)) {
      res.status(403).json({
        success: false,
        error: 'Origin not allowed',
      });
      return;
    }

    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).json({
        success: false,
        error: 'Method not allowed',
      });
      return;
    }

    const authHeader = req.get('Authorization') || '';
    const tokenPrefix = 'Bearer ';
    if (!authHeader.startsWith(tokenPrefix)) {
      res.status(401).json({
        success: false,
        error: 'Missing auth token',
      });
      return;
    }

    let decodedToken;
    try {
      const idToken = authHeader.substring(tokenPrefix.length).trim();
      decodedToken = await admin.auth().verifyIdToken(idToken);
    } catch (err) {
      functions.logger.warn('sendReport invalid token', {
        err: err.message,
      });
      res.status(401).json({
        success: false,
        error: 'Invalid auth token',
      });
      return;
    }

    let body = req.body;
    if (typeof body === 'string') {
      try {
        body = JSON.parse(body);
      } catch (err) {
        res.status(400).json({
          success: false,
          error: 'Invalid JSON body',
        });
        return;
      }
    }
    body = body && typeof body === 'object' ? body : {};

    const userId =
      typeof body.userId === 'string' ? body.userId.trim() : '';
    const message =
      typeof body.message === 'string' ? body.message.trim() : '';
    const appVersion =
      typeof body.appVersion === 'string' ? body.appVersion.trim() : '';
    const platform =
      typeof body.platform === 'string' ? body.platform.trim() : '';

    if (!userId || !message) {
      res.status(400).json({
        success: false,
        error: 'userId and message are required',
      });
      return;
    }

    if (decodedToken.uid !== userId) {
      res.status(403).json({
        success: false,
        error: 'userId does not match auth token',
      });
      return;
    }

    if (
      message.length < MIN_REPORT_MESSAGE_LENGTH ||
      message.length > MAX_REPORT_MESSAGE_LENGTH
    ) {
      res.status(400).json({
        success: false,
        error: `message must be between ${MIN_REPORT_MESSAGE_LENGTH} and ${MAX_REPORT_MESSAGE_LENGTH} characters`,
      });
      return;
    }

    const resendApiKey = process.env.RESEND_API_KEY;
    if (!resendApiKey) {
      functions.logger.error('sendReport missing RESEND_API_KEY secret');
      res.status(500).json({
        success: false,
        error: 'Report service is not configured',
      });
      return;
    }

    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    const reportRef = db.collection('reports').doc();
    const limitRef = db.collection('report_limits').doc(userId);

    try {
      await db.runTransaction(async (transaction) => {
        const limitSnap = await transaction.get(limitRef);

        let nextWindowStart = now;
        let nextCount = 1;

        if (limitSnap.exists) {
          const data = limitSnap.data() || {};
          const currentWindowStart = data.windowStart;
          const currentCount = Number(data.count || 0);
          const hasActiveWindow =
            currentWindowStart &&
            typeof currentWindowStart.toMillis === 'function' &&
            now.toMillis() - currentWindowStart.toMillis() <= REPORT_WINDOW_MS;

          if (hasActiveWindow) {
            if (currentCount >= REPORT_LIMIT_PER_DAY) {
              throw new RateLimitError('Limit reached');
            }
            nextWindowStart = currentWindowStart;
            nextCount = currentCount + 1;
          }
        }

        transaction.set(
          limitRef,
          {
            windowStart: nextWindowStart,
            count: nextCount,
          },
          { merge: true },
        );

        transaction.set(reportRef, {
          userId,
          message,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          ...(appVersion ? { appVersion } : {}),
          ...(platform ? { platform } : {}),
        });
      });
    } catch (err) {
      if (err instanceof RateLimitError) {
        res.status(429).json({
          success: false,
          error: 'Limit reached',
        });
        return;
      }

      functions.logger.error('sendReport firestore transaction failed', {
        err: err.message,
        userId,
      });
      res.status(500).json({
        success: false,
        error: 'Could not save report',
      });
      return;
    }

    try {
      const resend = new Resend(resendApiKey);
      const createdAtIso = now.toDate().toISOString();
      const escapedMessage = escapeHtml(message).replace(/\n/g, '<br>');

      const emailResult = await resend.emails.send({
        from: 'WorkyDay <hello@workyday.com>',
        to: 'miquelmassomoreno@gmail.com',
        subject: 'Nou report des de WorkyDay',
        html: `
          <h2>Nou report des de WorkyDay</h2>
          <p><strong>UserId:</strong> ${escapeHtml(userId)}</p>
          <p><strong>Data/hora:</strong> ${escapeHtml(createdAtIso)}</p>
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
      functions.logger.error('sendReport email failed', {
        err: err.message,
        reportId: reportRef.id,
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
      reportId: reportRef.id,
    });
  });
