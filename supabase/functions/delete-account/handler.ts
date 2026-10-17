export type DeletionRequest = {
  request_id: string;
  user_id: string | null;
  status: "pending" | "completed";
};

export interface DeletionBackend {
  verifyUser(token: string): Promise<string | null>;
  findRequest(id: string, secretHash: string): Promise<DeletionRequest | null>;
  startRequest(id: string, secretHash: string, userID: string): Promise<void>;
  photos(userID: string): Promise<Array<{ bucket_id: string; name: string }>>;
  removePhotos(bucket: string, names: string[]): Promise<void>;
  cleanup(userID: string): Promise<void>;
  deleteAuthUser(userID: string): Promise<void>;
  finishRequest(id: string, userID: string): Promise<void>;
}

const headers = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const reply = (status: number, data: Record<string, unknown>) =>
  new Response(JSON.stringify(data), { status, headers });

export function createDeletionHandler(backend: DeletionBackend) {
  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers });
    if (req.method !== "POST") return reply(405, { error: "Method not allowed" });
    let body;
    try { body = await req.json(); }
    catch { return reply(400, { error: "Invalid request" }); }
    if (body?.confirm !== true || typeof body.requestID !== "string" || !uuid.test(body.requestID)
      || typeof body.secret !== "string" || !/^[0-9a-f]{64}$/.test(body.secret)) {
      return reply(400, { error: "Invalid request" });
    }
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(body.secret));
    const secretHash = Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, "0")).join("");
    const id = body.requestID;
    try {
      let request = await backend.findRequest(id, secretHash);
      if (!request) {
        const token = req.headers.get("Authorization")?.match(/^Bearer (.+)$/i)?.[1];
        const userID = token ? await backend.verifyUser(token) : null;
        if (!userID) return reply(401, { error: "Authentication required" });
        // the target comes from verified auth, never a caller supplied user id
        await backend.startRequest(id, secretHash, userID);
        request = { request_id: id, user_id: userID, status: "pending" };
      }
      if (request.status === "completed") return reply(200, { deleted: true });
      if (!request.user_id) throw new Error("Missing deletion target");
      const userID = request.user_id;

      let previousBatch = "";
      while (true) {
        const files = await backend.photos(userID);
        if (files.length === 0) break;
        const batch = JSON.stringify(files);
        if (batch === previousBatch) throw new Error("Storage cleanup did not finish");
        previousBatch = batch;
        const groups = new Map<string, string[]>();
        for (const file of files) {
          const names = groups.get(file.bucket_id) ?? [];
          names.push(file.name);
          groups.set(file.bucket_id, names);
        }
        for (const [bucket, names] of groups) await backend.removePhotos(bucket, names);
      }
      await backend.cleanup(userID);
      await backend.deleteAuthUser(userID);
      await backend.finishRequest(id, userID);
      return reply(200, { deleted: true });
    } catch {
      // a retry may finish the same request while this call is still running
      try {
        const current = await backend.findRequest(id, secretHash);
        if (current?.status === "completed") return reply(200, { deleted: true });
      } catch { /* retry from the app when the server is reachable */ }
      console.error("Account deletion did not finish; request can be retried");
      return reply(503, { error: "Deletion did not finish. Please retry." });
    }
  };
}
