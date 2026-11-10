import { getFirestore } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { decryptRefreshToken, encryptRefreshToken } from "./google_drive_token_crypto";

const GOOGLE_OAUTH_CLIENT_ID =
  "209716874258-p9n2n9jmu87oqqu84703hf9kvuodokdn.apps.googleusercontent.com";
const GOOGLE_TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token";
const GOOGLE_REVOKE_ENDPOINT = "https://oauth2.googleapis.com/revoke";

const oauthClientSecret = defineSecret("GOOGLE_OAUTH_CLIENT_SECRET");
const tokenEncryptionKey = defineSecret("GOOGLE_DRIVE_TOKEN_ENCRYPTION_KEY");

interface GoogleTokenResponse {
  access_token?: unknown;
  refresh_token?: unknown;
  expires_in?: unknown;
  error?: unknown;
}

interface StoredToken {
  ciphertext: string;
  iv: string;
  tag: string;
}

function requireUid(uid: string | undefined): string {
  if (!uid) throw new HttpsError("unauthenticated", "Sign-in is required.");
  return uid;
}

function encryptionKey(): Buffer {
  const key = Buffer.from(tokenEncryptionKey.value(), "base64");
  if (key.length !== 32) {
    throw new HttpsError(
      "failed-precondition",
      "Google Drive token encryption is not configured.",
    );
  }
  return key;
}

function tokenDocument(uid: string) {
  return getFirestore("default1").collection("googleDriveAuthTokens").doc(uid);
}

function storedToken(data: Record<string, unknown>): StoredToken {
  const { ciphertext, iv, tag } = data;
  if (
    typeof ciphertext !== "string" ||
    typeof iv !== "string" ||
    typeof tag !== "string"
  ) {
    throw new HttpsError(
      "internal",
      "Stored Google Drive authorization is invalid.",
    );
  }
  return { ciphertext, iv, tag };
}

function accessTokenResponse(payload: GoogleTokenResponse): {
  accessToken: string;
  expiresIn: number;
} {
  if (
    typeof payload.access_token !== "string" ||
    payload.access_token.length === 0 ||
    typeof payload.expires_in !== "number" ||
    !Number.isFinite(payload.expires_in) ||
    payload.expires_in <= 0
  ) {
    throw new HttpsError(
      "unavailable",
      "Google did not return a valid access token.",
    );
  }
  return {
    accessToken: payload.access_token,
    expiresIn: Math.floor(payload.expires_in),
  };
}

async function exchangeAuthorizationCode(code: string): Promise<GoogleTokenResponse> {
  const response = await fetch(GOOGLE_TOKEN_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: GOOGLE_OAUTH_CLIENT_ID,
      client_secret: oauthClientSecret.value(),
      grant_type: "authorization_code",
      redirect_uri: "",
    }),
    signal: AbortSignal.timeout(15_000),
  });
  const payload = (await response.json()) as GoogleTokenResponse;
  if (!response.ok) {
    throw new HttpsError(
      "failed-precondition",
      "Google Drive authorization could not be completed. Please try again.",
    );
  }
  return payload;
}

async function refreshAccessToken(refreshToken: string): Promise<{
  accessToken: string;
  expiresIn: number;
}> {
  const response = await fetch(GOOGLE_TOKEN_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: GOOGLE_OAUTH_CLIENT_ID,
      client_secret: oauthClientSecret.value(),
      grant_type: "refresh_token",
      refresh_token: refreshToken,
    }),
    signal: AbortSignal.timeout(15_000),
  });
  const payload = (await response.json()) as GoogleTokenResponse;
  if (!response.ok) {
    if (payload.error === "invalid_grant") {
      throw new HttpsError(
        "failed-precondition",
        "Google Drive authorization expired. Reconnect Google Drive.",
      );
    }
    throw new HttpsError(
      "unavailable",
      "Google Drive could not be reached. Please try again.",
    );
  }
  return accessTokenResponse(payload);
}

export const connectGoogleDrive = onCall(
  { secrets: [oauthClientSecret, tokenEncryptionKey] },
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const code = request.data?.serverAuthCode;
    if (typeof code !== "string" || code.length === 0 || code.length > 8192) {
      throw new HttpsError("invalid-argument", "A valid authorization code is required.");
    }

    const tokenResponse = await exchangeAuthorizationCode(code);
    let refreshToken = tokenResponse.refresh_token;
    if (typeof refreshToken !== "string" || refreshToken.length === 0) {
      const existing = await tokenDocument(uid).get();
      if (existing.exists) {
        const previous = storedToken(existing.data()!);
        refreshToken = decryptRefreshToken(previous, encryptionKey());
      }
    }
    if (typeof refreshToken !== "string" || refreshToken.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "Google did not provide offline Drive access. Reconnect Drive and approve access.",
      );
    }

    const key = encryptionKey();
    const encrypted = encryptRefreshToken(refreshToken, key);
    await tokenDocument(uid).set({
      ...encrypted,
      updatedAt: Date.now(),
    });
    return accessTokenResponse(tokenResponse);
  },
);

export const getGoogleDriveAccessToken = onCall(
  { secrets: [oauthClientSecret, tokenEncryptionKey] },
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const snapshot = await tokenDocument(uid).get();
    if (!snapshot.exists) {
      throw new HttpsError(
        "failed-precondition",
        "Google Drive has not been connected.",
      );
    }
    const refreshToken = decryptRefreshToken(
      storedToken(snapshot.data()!),
      encryptionKey(),
    );
    try {
      return await refreshAccessToken(refreshToken);
    } catch (error) {
      if (error instanceof HttpsError && error.code === "failed-precondition") {
        await tokenDocument(uid).delete();
      }
      throw error;
    }
  },
);

export const disconnectGoogleDrive = onCall(
  { secrets: [oauthClientSecret, tokenEncryptionKey] },
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const reference = tokenDocument(uid);
    const snapshot = await reference.get();
    if (!snapshot.exists) return { disconnected: true, revoked: true };

    const refreshToken = decryptRefreshToken(
      storedToken(snapshot.data()!),
      encryptionKey(),
    );
    await reference.delete();

    try {
      const response = await fetch(GOOGLE_REVOKE_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ token: refreshToken }),
        signal: AbortSignal.timeout(15_000),
      });
      if (!response.ok) {
        logger.warn("Google Drive token revocation was rejected.");
        return { disconnected: true, revoked: false };
      }
      return { disconnected: true, revoked: true };
    } catch (error) {
      logger.warn("Google Drive token revocation request failed.", error);
      return { disconnected: true, revoked: false };
    }
  },
);
