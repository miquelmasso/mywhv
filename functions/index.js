const functions = require('firebase-functions');
const admin = require('firebase-admin');
const fetch = require('node-fetch');
const cheerio = require('cheerio');

admin.initializeApp();

const REGION = 'australia-southeast1';

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
