const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const DEFAULT_COLLECTIONS = [
  'restaurants',
  'harvest_places',
  'visa_postcodes',
];

const projectRoot = __dirname;
const exportDir = path.join(projectRoot, 'export');
const serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT
  ? path.resolve(process.env.FIREBASE_SERVICE_ACCOUNT)
  : path.join(projectRoot, 'serviceAccountKey.json');

function printUsage() {
  console.log(`
Usage:
  node export.js <collection-name>
  node export.js --all

Examples:
  node export.js restaurants
  node export.js --all

Service account:
  Place serviceAccountKey.json next to export.js
  or set FIREBASE_SERVICE_ACCOUNT=/absolute/path/to/serviceAccountKey.json
`);
}

function ensureServiceAccountFile() {
  if (!fs.existsSync(serviceAccountPath)) {
    throw new Error(
      `Missing Firebase credentials.
Expected service account file at:
${serviceAccountPath}

Place your serviceAccountKey.json there or set FIREBASE_SERVICE_ACCOUNT.`,
    );
  }
}

function ensureExportDirectory() {
  fs.mkdirSync(exportDir, { recursive: true });
}

function normalizeFirestoreValue(value) {
  if (value === null || value === undefined) {
    return value;
  }

  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate().toISOString();
  }

  if (value instanceof admin.firestore.GeoPoint) {
    return {
      latitude: value.latitude,
      longitude: value.longitude,
    };
  }

  if (value instanceof admin.firestore.DocumentReference) {
    return value.path;
  }

  if (Buffer.isBuffer(value)) {
    return value.toString('base64');
  }

  if (Array.isArray(value)) {
    return value.map(normalizeFirestoreValue);
  }

  if (typeof value === 'object') {
    const normalized = {};
    for (const [key, nestedValue] of Object.entries(value)) {
      normalized[key] = normalizeFirestoreValue(nestedValue);
    }
    return normalized;
  }

  return value;
}

async function exportCollection(db, collectionName) {
  console.log(`Starting export for collection: ${collectionName}`);

  let snapshot;
  try {
    snapshot = await db.collection(collectionName).get();
  } catch (error) {
    throw new Error(
      `Failed to fetch collection "${collectionName}": ${error.message}`,
    );
  }

  if (snapshot.empty) {
    console.warn(`Collection "${collectionName}" is empty.`);
  }

  const documents = snapshot.docs.map((doc) => ({
    id: doc.id,
    ...normalizeFirestoreValue(doc.data()),
  }));

  const outputPath = path.join(exportDir, `${collectionName}.json`);
  fs.writeFileSync(outputPath, JSON.stringify(documents, null, 2), 'utf8');

  console.log(
    `Exported ${documents.length} document(s) from "${collectionName}" to ${outputPath}`,
  );
}

function parseCollectionsFromArgs(argv) {
  const arg = argv[2];

  if (!arg || arg === '--all') {
    return DEFAULT_COLLECTIONS;
  }

  if (arg === '--help' || arg === '-h') {
    printUsage();
    process.exit(0);
  }

  return [arg];
}

async function main() {
  try {
    ensureServiceAccountFile();
    ensureExportDirectory();

    const serviceAccount = require(serviceAccountPath);

    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });

    const db = admin.firestore();
    const collections = parseCollectionsFromArgs(process.argv);

    for (const collectionName of collections) {
      await exportCollection(db, collectionName);
    }

    console.log('Export completed successfully.');
  } catch (error) {
    console.error('Export failed.');
    console.error(error.message);
    process.exitCode = 1;
  } finally {
    if (admin.apps.length > 0) {
      await admin.app().delete();
    }
  }
}

main();
