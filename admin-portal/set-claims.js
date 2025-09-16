// set-claims.js
const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.cert(require('./serviceAccount.json')),
});

async function setRole(uid, role) {
  if (!['admin','mod'].includes(role)) {
    throw new Error('Invalid role: use "admin" or "mod"');
  }
  await admin.auth().setCustomUserClaims(uid, { role });
  console.log(`Set role=${role} for uid=${uid}`);
}

(async () => {
  try {
    await setRole('YALKXC9leXaibhbrX9eu42h6Tux1', 'admin'); // replace with your admin user's UID
    console.log('Done. Now sign out/in on the admin page to refresh token.');
    process.exit(0);
  } catch (e) {
    console.error('Error setting custom claim:', e);
    process.exit(1);
  }
})();
