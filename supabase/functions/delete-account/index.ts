import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { createDeletionHandler, type DeletionBackend } from "./handler.ts";

const client = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const backend: DeletionBackend = {
  async verifyUser(token) {
    const { data, error } = await client.auth.getUser(token);
    if (error) return null;
    return data.user?.id ?? null;
  },
  async findRequest(id, secretHash) {
    const { data, error } = await client.from("account_deletion_requests")
      .select("request_id,user_id,status").eq("request_id", id).eq("secret_hash", secretHash).maybeSingle();
    if (error) throw error;
    return data;
  },
  async startRequest(id, secretHash, userID) {
    const { error } = await client.from("account_deletion_requests")
      .insert({ request_id: id, secret_hash: secretHash, user_id: userID });
    if (error) throw error;
  },
  async photos(userID) {
    const { data, error } = await client.rpc("account_deletion_photos", { p_user_id: userID });
    if (error) throw error;
    return data ?? [];
  },
  async removePhotos(bucket, names) {
    const { error } = await client.storage.from(bucket).remove(names);
    if (error) throw error;
  },
  async cleanup(userID) {
    const { error } = await client.rpc("cleanup_account_data", { p_user_id: userID });
    if (error) throw error;
  },
  async deleteAuthUser(userID) {
    const { error } = await client.auth.admin.deleteUser(userID);
    if (error && error.code !== "user_not_found") throw error;
  },
  async finishRequest(id, userID) {
    const { error } = await client.from("account_deletion_requests")
      .update({ status: "completed", user_id: null, completed_at: new Date().toISOString() })
      .or(`request_id.eq.${id},user_id.eq.${userID}`);
    if (error) throw error;
  },
};

Deno.serve(createDeletionHandler(backend));
