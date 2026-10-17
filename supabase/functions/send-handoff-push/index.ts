// sends pickup alerts for handoffs
// deploy with supabase functions deploy

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { SignJWT, importPKCS8 } from "https://deno.land/x/jose@v5.9.6/index.ts";

type ListingRow = {
  id: string;
  title: string;
  status: string;
  posted_by: string;
  claimed_by: string | null;
  contact_instructions: string | null;
  moderation_status: string;
};

type MessageRow = {
  listing_id: string;
  sender_id: string;
  body: string;
};

type Coordination = {
  instructionsPublished?: boolean;
  meetupAddress?: string;
  timeslot?: string;
  handoffSpot?: string;
};

type WebhookPayload = {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  record: Record<string, unknown>;
  old_record?: Record<string, unknown>;
};

type PushNote = {
  recipientUserID: string;
  type: string;
  title: string;
  body: string;
  listingID: string;
  listingTitle: string;
};

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  let payload: WebhookPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  const notifications = await buildNotifications(payload);
  if (notifications.length === 0) {
    return new Response(JSON.stringify({ sent: 0 }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  let sent = 0;
  for (const note of notifications) {
    const tokens = await fetchTokens(note.recipientUserID);
    for (const token of tokens) {
      if (await sendAPNs(token, note)) sent += 1;
    }
  }

  return new Response(JSON.stringify({ sent }), {
    headers: { "Content-Type": "application/json" },
  });
});

async function buildNotifications(payload: WebhookPayload): Promise<PushNote[]> {
  if (payload.table === "listing_messages" && payload.type === "INSERT") {
    return notificationsForMessage(payload.record as unknown as MessageRow);
  }
  if (payload.table === "listings" && payload.type === "UPDATE") {
    return notificationsForListingUpdate(
      payload.record as unknown as ListingRow,
      (payload.old_record ?? {}) as unknown as ListingRow,
    );
  }
  return [];
}

async function notificationsForMessage(row: MessageRow): Promise<PushNote[]> {
  if (!row.listing_id || !row.sender_id) return [];

  const { data: listing } = await supabase
    .from("listings")
    .select("id, title, posted_by, claimed_by, moderation_status")
    .eq("id", row.listing_id)
    .maybeSingle();

  if (!listing || listing.moderation_status !== "approved") return [];

  const postedBy = listing.posted_by as string;
  const claimedBy = listing.claimed_by as string | null;
  const recipient = row.sender_id === postedBy ? claimedBy : postedBy;

  if (!recipient || recipient === row.sender_id) return [];

  const { data: blocked, error: blockError } = await supabase.rpc("users_are_blocked", {
    first_user: row.sender_id,
    second_user: recipient,
  });
  if (blockError || blocked !== false) return [];

  return [{
    recipientUserID: recipient,
    type: "message",
    title: "SharePlate",
    body: `${row.body} — ${listing.title}`,
    listingID: listing.id as string,
    listingTitle: listing.title as string,
  }];
}

function isPickedUpStatus(status: string | undefined): boolean {
  return status === "pickedUp" || status === "picked_up" || status === "collected";
}

function isReadyStatus(status: string | undefined): boolean {
  return status === "readyForPickup" || status === "ready_for_pickup";
}

function notificationsForListingUpdate(
  record: ListingRow,
  old: ListingRow,
): PushNote[] {
  if (record.moderation_status !== "approved") return [];
  const notes: PushNote[] = [];
  const title = record.title ?? "Food";
  const listingID = record.id;

  if (!old.claimed_by && record.claimed_by && record.posted_by) {
    notes.push({
      recipientUserID: record.posted_by,
      type: "listing_reserved",
      title: "SharePlate",
      body: `Someone reserved "${title}". Set pickup instructions.`,
      listingID,
      listingTitle: title,
    });
  }

  const oldCoord = decodeCoordination(old.contact_instructions);
  const newCoord = decodeCoordination(record.contact_instructions);
  if (
    record.claimed_by &&
    !coordinationReady(oldCoord) &&
    coordinationReady(newCoord)
  ) {
    notes.push({
      recipientUserID: record.claimed_by,
      type: "instructions_updated",
      title: "SharePlate",
      body: `Pickup instructions are ready for "${title}".`,
      listingID,
      listingTitle: title,
    });
  }

  if (
    record.claimed_by &&
    !isReadyStatus(old.status) &&
    isReadyStatus(record.status)
  ) {
    notes.push({
      recipientUserID: record.claimed_by,
      type: "ready_for_pickup",
      title: "SharePlate",
      body: `"${title}" is ready for pickup.`,
      listingID,
      listingTitle: title,
    });
  }

  if (
    record.posted_by &&
    !isPickedUpStatus(old.status) &&
    isPickedUpStatus(record.status)
  ) {
    notes.push({
      recipientUserID: record.posted_by,
      type: "picked_up",
      title: "SharePlate",
      body: `"${title}" was marked picked up.`,
      listingID,
      listingTitle: title,
    });
  }

  if (old.claimed_by && !record.claimed_by && !isPickedUpStatus(record.status)) {
    const releasedBy = record.posted_by;
    const recipient = old.claimed_by === releasedBy
      ? old.posted_by
      : old.claimed_by;
    if (recipient && recipient !== releasedBy) {
      notes.push({
        recipientUserID: recipient,
        type: "reservation_released",
        title: "SharePlate",
        body: `Reservation for "${title}" was released.`,
        listingID,
        listingTitle: title,
      });
    } else if (old.claimed_by && old.claimed_by !== releasedBy) {
      notes.push({
        recipientUserID: old.claimed_by,
        type: "reservation_released",
        title: "SharePlate",
        body: `Reservation for "${title}" was released.`,
        listingID,
        listingTitle: title,
      });
    }
  }

  return notes;
}

function decodeCoordination(raw: string | null | undefined): Coordination {
  if (!raw) return {};
  try {
    return JSON.parse(raw) as Coordination;
  } catch {
    return {};
  }
}

function coordinationReady(coord: Coordination): boolean {
  return coord.instructionsPublished === true &&
    Boolean(coord.meetupAddress?.trim()) &&
    Boolean(coord.timeslot) &&
    Boolean(coord.handoffSpot);
}

async function fetchTokens(userID: string): Promise<string[]> {
  const { data } = await supabase
    .from("device_tokens")
    .select("token")
    .eq("user_id", userID);
  return (data ?? []).map((row) => row.token as string);
}

let cachedJwt: { token: string; expires: number } | null = null;

async function apnsJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && cachedJwt.expires > now + 60) {
    return cachedJwt.token;
  }

  const keyID = Deno.env.get("APNS_KEY_ID")!;
  const teamID = Deno.env.get("APNS_TEAM_ID")!;
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY")!;
  const key = await importPKCS8(privateKey, "ES256");

  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyID })
    .setIssuer(teamID)
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);

  cachedJwt = { token, expires: now + 3600 };
  return token;
}

async function sendAPNs(deviceToken: string, note: PushNote): Promise<boolean> {
  const bundleID = Deno.env.get("APNS_BUNDLE_ID");
  const keyID = Deno.env.get("APNS_KEY_ID");
  const teamID = Deno.env.get("APNS_TEAM_ID");
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY");

  if (!bundleID || !keyID || !teamID || !privateKey) {
    console.error("APNs secrets not configured");
    return false;
  }

  const production = Deno.env.get("APNS_PRODUCTION") === "true";
  const host = production
    ? "api.push.apple.com"
    : "api.sandbox.push.apple.com";

  const jwt = await apnsJwt();
  const payload = {
    aps: {
      alert: { title: note.title, body: note.body },
      sound: "default",
    },
    type: note.type,
    listing_id: note.listingID,
    listing_title: note.listingTitle,
    body: note.body,
  };

  const response = await fetch(`https://${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": bundleID,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    console.error("APNs error", response.status, await response.text());
  }
  return response.ok;
}
