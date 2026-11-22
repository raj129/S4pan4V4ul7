/**
 * Cloud Functions for the end-to-end encrypted chat.
 *
 * Message bodies are ciphertext the server cannot read, so FCM omits message
 * content. The client displays a generic alert and records device delivery.
 * GIPHY search stays in the client, as required by GIPHY's API guidelines.
 */
import { initializeApp } from "firebase-admin/app";
import { FieldPath, getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger, setGlobalOptions } from "firebase-functions/v2";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import {
  connectGoogleDrive,
  getGoogleDriveAccessToken,
} from "./google_drive_tokens";

initializeApp();

/** The app uses a named Firestore database, not "(default)". */
const DATABASE_ID = "default1";

/**
 * Must be the region of the `default1` database: a Firestore trigger has to
 * run in the same location as its database, otherwise the deploy fails.
 * Check it in the Firebase console under Firestore -> Databases.
 */
const REGION = "asia-south1";

/** At most one visible alert per thread and recipient in this window. */
const MIN_ALERT_INTERVAL_MS = 30 * 1000;

/** FCM accepts at most 500 tokens per multicast. */
const MAX_TOKENS_PER_SEND = 500;

const STALE_TOKEN_ERRORS = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

setGlobalOptions({ region: REGION, maxInstances: 10 });

const db = getFirestore(DATABASE_ID);

async function acquireAlertSlot(
  threadId: string,
  recipientId: string,
): Promise<boolean> {
  const ref = db.collection("pushThrottle").doc(`${threadId}_${recipientId}`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    const last = snap.get("lastSentAt");
    if (typeof last === "number" && now - last < MIN_ALERT_INTERVAL_MS) {
      return false;
    }
    tx.set(ref, { lastSentAt: now });
    return true;
  });
}

export const onChatMessageCreated = onDocumentCreated(
  {
    database: DATABASE_ID,
    document: "threads/{threadId}/messages/{messageId}",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const { threadId, messageId } = event.params;
    const message = snapshot.data();
    const senderId = message.senderId as string | undefined;

    if (!senderId || message.deletedForEveryone === true) return;
    if (message.threadId !== threadId) {
      logger.warn("Message threadId does not match its path", {
        threadId,
        messageId,
      });
      return;
    }

    // Thread IDs are the sorted "<uidA>_<uidB>" pair (see ChatThread.buildId).
    const participants = threadId.split("_");
    if (participants.length !== 2 || !participants.includes(senderId)) {
      logger.warn("Unexpected thread id or sender", { threadId, messageId });
      return;
    }
    const recipientId = participants.find((uid) => uid !== senderId);
    if (!recipientId) return;

    // Only notify for a real thread that lists both people, never for a
    // message written into a thread path that was never created.
    const threadSnap = await db.collection("threads").doc(threadId).get();
    const participantIds = threadSnap.get("participantIds");
    if (
      !threadSnap.exists ||
      !Array.isArray(participantIds) ||
      !participantIds.includes(senderId) ||
      !participantIds.includes(recipientId)
    ) {
      logger.warn("Thread missing or sender/recipient not participants", {
        threadId,
        messageId,
      });
      return;
    }

    const isRingRequest = message.eventType === "ringRequest";
    const notify = isRingRequest
      ? true
      : await acquireAlertSlot(threadId, recipientId);
    let ringSettings = {
      enabled: true,
      source: "system",
      mode: "ringtone",
      ringSoundEnabled: true,
      vibrationEnabled: true,
      ringtoneUri: "",
      timeoutSeconds: 5,
      vibrationPattern: "standard",
      flashlightEnabled: false,
      flashPattern: "slowBlink",
      notificationTitle: "",
      notificationBody: "",
    };
    if (isRingRequest) {
      try {
        const settings = await db
          .collection("users")
          .doc(recipientId)
          .collection("private")
          .doc("ringAlertPreferences")
          .get();
        if (settings.exists) {
          const value = settings.data() ?? {};
          const legacyMode =
            value.mode === "ringAndVibrate" ||
            value.mode === "ringtone" ||
            value.mode === "vibrate" ||
            value.mode === "silent"
              ? value.mode
              : "ringAndVibrate";
          const ringSoundEnabled =
            typeof value.ringSoundEnabled === "boolean"
              ? value.ringSoundEnabled
              : legacyMode === "ringAndVibrate" || legacyMode === "ringtone";
          const vibrationEnabled =
            typeof value.vibrationEnabled === "boolean"
              ? value.vibrationEnabled
              : legacyMode === "ringAndVibrate" || legacyMode === "vibrate";
          const hasLegacyNotificationDefaults =
            value.notificationTitle === "Ring request" &&
            value.notificationBody === "Someone is asking you to ring.";
          ringSettings = {
            enabled: value.enabled !== false,
            source:
              value.source === "custom" ||
              (value.source == null && typeof value.mode === "string")
                ? "custom"
                : "system",
            mode: ringSoundEnabled
              ? "ringtone"
              : vibrationEnabled
                ? "vibrate"
                : "silent",
            ringSoundEnabled,
            vibrationEnabled,
            ringtoneUri:
              typeof value.ringtoneUri === "string" ? value.ringtoneUri : "",
            timeoutSeconds:
              typeof value.timeoutSeconds === "number" &&
              [5, 10, 15, 30, 45, 60, 90, 120].includes(value.timeoutSeconds)
                ? value.timeoutSeconds
                : 5,
            vibrationPattern: [
              "standard",
              "shortPulses",
              "longPulses",
            ].includes(value.vibrationPattern)
              ? value.vibrationPattern
              : "standard",
            flashlightEnabled: value.flashlightEnabled === true,
            flashPattern: [
              "slowBlink",
              "doubleBlink",
              "fastBlink",
            ].includes(value.flashPattern)
              ? value.flashPattern
              : "slowBlink",
            notificationTitle:
              !hasLegacyNotificationDefaults &&
                typeof value.notificationTitle === "string"
                ? value.notificationTitle.slice(0, 80)
                : "",
            notificationBody:
              !hasLegacyNotificationDefaults &&
                typeof value.notificationBody === "string"
                ? value.notificationBody.slice(0, 240)
                : "",
          };
        }
      } catch (error) {
        logger.warn("Ring request preferences could not be read", {
          threadId,
          messageId,
          recipientId,
          error,
        });
        ringSettings.enabled = false;
      }
    }
    const tokensRef = db
      .collection("users")
      .doc(recipientId)
      .collection("private")
      .doc("devices")
      .collection("tokens");
    const tokenDocs = await tokensRef.select(FieldPath.documentId()).get();
    const tokens = tokenDocs.docs.map((d) => d.id);
    if (tokens.length === 0) return;

    const stale: string[] = [];
    for (let i = 0; i < tokens.length; i += MAX_TOKENS_PER_SEND) {
      const batch = tokens.slice(i, i + MAX_TOKENS_PER_SEND);
      const response = await getMessaging().sendEachForMulticast({
        tokens: batch,
        data: {
          threadId,
          messageId,
          senderId,
          notify: notify ? "true" : "false",
          ...(isRingRequest
            ? {
                eventType: "ringRequest",
                ringEnabled: ringSettings.enabled ? "true" : "false",
                ringSource: ringSettings.source,
                ringMode: ringSettings.mode,
                ringSoundEnabled: ringSettings.ringSoundEnabled
                  ? "true"
                  : "false",
                vibrationEnabled: ringSettings.vibrationEnabled
                  ? "true"
                  : "false",
                ringtoneUri: ringSettings.ringtoneUri,
                ringTimeoutSeconds: String(ringSettings.timeoutSeconds),
                ringVibrationPattern: ringSettings.vibrationPattern,
                ringFlashlightEnabled: ringSettings.flashlightEnabled
                  ? "true"
                  : "false",
                ringFlashPattern: ringSettings.flashPattern,
                ringTitle: ringSettings.notificationTitle,
                ringBody: ringSettings.notificationBody,
              }
            : {}),
        },
        android: {
          priority: "high",
        },
      });
      response.responses.forEach((r, idx) => {
        if (!r.success && r.error && STALE_TOKEN_ERRORS.has(r.error.code)) {
          stale.push(batch[idx]);
        }
      });
    }

    if (stale.length > 0) {
      const writer = db.bulkWriter();
      stale.forEach((token) => writer.delete(tokensRef.doc(token)));
      await writer.close();
    }
    logger.info("Chat push sent", {
      threadId,
      messageId,
      devices: tokens.length,
      pruned: stale.length,
    });
  },
);

export { connectGoogleDrive, getGoogleDriveAccessToken };
