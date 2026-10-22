const { readFileSync } = require('node:fs');
const path = require('node:path');
const { after, before, beforeEach, test } = require('node:test');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc } = require('firebase/firestore');
const { getBytes, ref, uploadBytes } = require('firebase/storage');

const projectId = 'demo-shadow4726262';
const repositoryRoot = path.resolve(__dirname, '..', '..');
let testEnvironment;

before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: readFileSync(path.join(repositoryRoot, 'firestore.rules'), 'utf8'),
    },
    storage: {
      rules: readFileSync(path.join(repositoryRoot, 'storage.rules'), 'utf8'),
    },
  });
});

beforeEach(async () => {
  await testEnvironment.clearFirestore();
  await testEnvironment.clearStorage();
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'threads/alice_bob'), {
      participantIds: ['alice', 'bob'],
    });
  });
});

after(async () => {
  await testEnvironment.cleanup();
});

test('Firestore lets a participant write and read their live location', async () => {
  const participantDb = testEnvironment.authenticatedContext('alice').firestore();
  const location = doc(
    participantDb,
    'threads/alice_bob/live_locations/session-1',
  );
  const now = Date.now();
  const payload = {
    sessionId: 'session-1',
    threadId: 'alice_bob',
    userId: 'alice',
    isActive: true,
    startedAt: now,
    expiresAt: now + 15 * 60 * 1000,
    lastUpdatedAt: now,
    encryptedPayload: 'opaque-ciphertext',
  };

  await assertSucceeds(setDoc(location, payload));
  await assertSucceeds(getDoc(location));
});

test('Firestore allows live-location timestamps slightly ahead of server time', async () => {
  const participantDb = testEnvironment.authenticatedContext('alice').firestore();
  const location = doc(
    participantDb,
    'threads/alice_bob/live_locations/client-clock-skew',
  );
  const startedAt = Date.now() + 30_000;

  await assertSucceeds(
    setDoc(location, {
      sessionId: 'client-clock-skew',
      threadId: 'alice_bob',
      userId: 'alice',
      isActive: true,
      startedAt,
      expiresAt: startedAt + 15 * 60 * 1000,
      lastUpdatedAt: startedAt,
      encryptedPayload: 'opaque-ciphertext',
    }),
  );
});

test('Firestore rejects live-location timestamps beyond the clock-skew allowance', async () => {
  const participantDb = testEnvironment.authenticatedContext('alice').firestore();
  const location = doc(
    participantDb,
    'threads/alice_bob/live_locations/excessive-clock-skew',
  );
  const startedAt = Date.now() + 120_000;

  await assertFails(
    setDoc(location, {
      sessionId: 'excessive-clock-skew',
      threadId: 'alice_bob',
      userId: 'alice',
      isActive: true,
      startedAt,
      expiresAt: startedAt + 15 * 60 * 1000,
      lastUpdatedAt: startedAt,
      encryptedPayload: 'opaque-ciphertext',
    }),
  );
});

test('Firestore denies nonparticipants and forged live-location owners', async () => {
  const outsiderDb = testEnvironment.authenticatedContext('mallory').firestore();
  const forgedOwnerLocation = doc(
    outsiderDb,
    'threads/alice_bob/live_locations/session-1',
  );
  const validOwnerLocation = doc(
    outsiderDb,
    'threads/alice_bob/live_locations/session-2',
  );
  const payload = {
    sessionId: 'session-1',
    threadId: 'alice_bob',
    userId: 'mallory',
    isActive: true,
    startedAt: 1,
    expiresAt: 2,
    lastUpdatedAt: 1,
    encryptedPayload: 'opaque-ciphertext',
  };

  await assertFails(setDoc(forgedOwnerLocation, payload));
  await assertFails(setDoc(validOwnerLocation, payload));
});

test('Firestore denies writing another participant’s live location', async () => {
  const bobDb = testEnvironment.authenticatedContext('bob').firestore();
  const location = doc(
    bobDb,
    'threads/alice_bob/live_locations/session-3',
  );
  const now = Date.now();

  await assertFails(
    setDoc(location, {
      sessionId: 'session-3',
      threadId: 'alice_bob',
      userId: 'alice',
      isActive: true,
      startedAt: now,
      expiresAt: now + 15 * 60 * 1000,
      lastUpdatedAt: now,
      encryptedPayload: 'opaque-ciphertext',
    }),
  );
});

test('Storage lets thread participants upload and read encrypted attachments', async () => {
  const participantStorage = testEnvironment.authenticatedContext('alice').storage();
  const attachment = ref(
    participantStorage,
    'chat_media/alice_bob/message-1/attachment.bin',
  );

  await assertSucceeds(
    uploadBytes(attachment, new Uint8Array([1, 2, 3]), {
      contentType: 'application/octet-stream',
    }),
  );
  await assertSucceeds(getBytes(attachment));
});

test('Storage denies outsiders and invalid attachment content types', async () => {
  const outsiderStorage = testEnvironment
    .authenticatedContext('mallory')
    .storage();
  const outsiderAttachment = ref(
    outsiderStorage,
    'chat_media/alice_bob/message-1/attachment.bin',
  );
  const participantStorage = testEnvironment.authenticatedContext('alice').storage();
  const invalidAttachment = ref(
    participantStorage,
    'chat_media/alice_bob/message-2/attachment.bin',
  );

  await assertFails(
    uploadBytes(outsiderAttachment, new Uint8Array([1]), {
      contentType: 'application/octet-stream',
    }),
  );
  await assertFails(
    uploadBytes(invalidAttachment, new Uint8Array([1]), {
      contentType: 'text/plain',
    }),
  );
});
