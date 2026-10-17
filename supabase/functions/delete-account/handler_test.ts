import assert from "node:assert/strict";
import { createDeletionHandler, type DeletionBackend, type DeletionRequest } from "./handler.ts";

const user = "10000000-0000-4000-8000-000000000001";
const requestID = "20000000-0000-4000-8000-000000000002";
const secret = "a".repeat(64);

function fixture() {
  let record: (DeletionRequest & { hash: string }) | null = null;
  let files = [{ bucket_id: "listing-photos", name: `${user}/photo.jpg` }];
  const calls: string[] = [];
  let failAt = "";
  const backend: DeletionBackend = {
    verifyUser(token) { return Promise.resolve(token === "valid" ? user : null); },
    findRequest(id, hash) { return Promise.resolve(record?.request_id === id && record.hash === hash ? { ...record } : null); },
    startRequest(id, hash, userID) {
      assert.equal(userID, user);
      assert.notEqual(hash, secret);
      if (record) throw new Error("duplicate request");
      record = { request_id: id, user_id: userID, status: "pending", hash };
      return Promise.resolve();
    },
    photos() { return Promise.resolve(files); },
    removePhotos(bucket, names) {
      calls.push("photos");
      if (failAt === "photos") { failAt = ""; throw new Error("storage offline"); }
      files = files.filter(file => file.bucket_id !== bucket || !names.includes(file.name));
      return Promise.resolve();
    },
    cleanup(id) {
      assert.equal(id, user);
      calls.push("cleanup");
      return Promise.resolve();
    },
    deleteAuthUser(id) {
      assert.equal(id, user);
      calls.push("auth");
      if (failAt === "auth") { failAt = ""; throw new Error("auth offline"); }
      return Promise.resolve();
    },
    finishRequest() {
      calls.push("finish");
      if (failAt === "finish") { failAt = ""; throw new Error("database offline"); }
      record!.status = "completed";
      record!.user_id = null;
      return Promise.resolve();
    },
  };
  const handler = createDeletionHandler(backend);
  return {
    calls,
    fail(stage: string) { failAt = stage; },
    send(token = "valid", overrides: Record<string, unknown> = {}) {
      return handler(new Request("https://example.org/delete-account", {
        method: "POST", headers: token ? { Authorization: `Bearer ${token}` } : {},
        body: JSON.stringify({ requestID, secret, confirm: true, ...overrides }),
      }));
    },
  };
}

Deno.test("deletion verifies auth and ignores a caller supplied target", async () => {
  const f = fixture();
  assert.equal((await f.send("invalid")).status, 401);
  assert.equal((await f.send("", { confirm: false })).status, 400);
  assert.deepEqual(f.calls, []);
  const response = await f.send("valid", { userID: "someone-else" });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { deleted: true });
  assert.deepEqual(f.calls, ["photos", "cleanup", "auth", "finish"]);
});

Deno.test("storage failure preserves a secure retry without deleting auth", async () => {
  const f = fixture();
  f.fail("photos");
  assert.equal((await f.send()).status, 503);
  assert.deepEqual(f.calls, ["photos"]);
  assert.equal((await f.send("", { secret: "b".repeat(64) })).status, 401);
  assert.equal((await f.send("")).status, 200);
  assert.deepEqual(f.calls, ["photos", "photos", "cleanup", "auth", "finish"]);
});

Deno.test("auth deletion must succeed before confirming completion", async () => {
  const f = fixture();
  f.fail("auth");
  assert.equal((await f.send()).status, 503);
  assert.ok(!f.calls.includes("finish"));
  assert.equal((await f.send("")).status, 200);
});

Deno.test("lost responses and interrupted completion do not require a new account", async () => {
  const f = fixture();
  f.fail("finish");
  assert.equal((await f.send()).status, 503);
  assert.equal((await f.send("")).status, 200);
  const count = f.calls.length;
  assert.equal((await f.send("")).status, 200);
  assert.equal(f.calls.length, count);
});
