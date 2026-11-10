const { randomBytes } = require("node:crypto");
const { test } = require("node:test");
const assert = require("node:assert/strict");
const {
  decryptRefreshToken,
  encryptRefreshToken,
} = require("../lib/google_drive_token_crypto.js");

test("refresh tokens can be encrypted and decrypted with the same key", () => {
  const key = randomBytes(32);
  const token = "refresh-token-value";

  const encrypted = encryptRefreshToken(token, key);

  assert.notEqual(encrypted.ciphertext, token);
  assert.equal(decryptRefreshToken(encrypted, key), token);
});

test("encrypted refresh tokens reject a different encryption key", () => {
  const encrypted = encryptRefreshToken("refresh-token-value", randomBytes(32));

  assert.throws(() => decryptRefreshToken(encrypted, randomBytes(32)));
});
