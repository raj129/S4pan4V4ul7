import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";

export interface EncryptedRefreshToken {
  ciphertext: string;
  iv: string;
  tag: string;
}

export function encryptRefreshToken(
  refreshToken: string,
  encryptionKey: Buffer,
): EncryptedRefreshToken {
  if (encryptionKey.length !== 32) {
    throw new Error("Google Drive token encryption key must be 32 bytes.");
  }
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", encryptionKey, iv);
  const ciphertext = Buffer.concat([
    cipher.update(refreshToken, "utf8"),
    cipher.final(),
  ]);
  return {
    ciphertext: ciphertext.toString("base64"),
    iv: iv.toString("base64"),
    tag: cipher.getAuthTag().toString("base64"),
  };
}

export function decryptRefreshToken(
  encrypted: EncryptedRefreshToken,
  encryptionKey: Buffer,
): string {
  if (encryptionKey.length !== 32) {
    throw new Error("Google Drive token encryption key must be 32 bytes.");
  }
  const decipher = createDecipheriv(
    "aes-256-gcm",
    encryptionKey,
    Buffer.from(encrypted.iv, "base64"),
  );
  decipher.setAuthTag(Buffer.from(encrypted.tag, "base64"));
  return Buffer.concat([
    decipher.update(Buffer.from(encrypted.ciphertext, "base64")),
    decipher.final(),
  ]).toString("utf8");
}
