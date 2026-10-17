// Sign in with Apple token revocation, used when an account is deleted (App Store requirement:
// https://developer.apple.com/support/offering-account-deletion-in-your-app/).
// Needs APPLE_TEAM_ID, APPLE_KEY_ID and APPLE_PRIVATE_KEY (the .p8 key with Sign in with Apple
// enabled). Without them this does nothing; it never blocks deleting an account.

const encoder = new TextEncoder();
const base64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

async function clientSecret(clientId: string): Promise<string | null> {
  const teamId = Deno.env.get("APPLE_TEAM_ID");
  const keyId = Deno.env.get("APPLE_KEY_ID");
  const pem = Deno.env.get("APPLE_PRIVATE_KEY");
  if (!teamId || !keyId || !pem) return null;
  const der = Uint8Array.from(atob(pem.replace(/-----[^-]+-----/g, "").replace(/\\n|\s/g, "")), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: keyId })));
  const claims = base64url(encoder.encode(JSON.stringify({
    iss: teamId, iat: now, exp: now + 300, aud: "https://appleid.apple.com", sub: clientId,
  })));
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(`${header}.${claims}`)));
  return `${header}.${claims}.${base64url(signature)}`;
}

/** Exchanges the app's fresh authorization code for a token and revokes it. Returns whether it worked. */
export async function revokeAppleSignIn(authorizationCode: string): Promise<boolean> {
  try {
    const clientId = Deno.env.get("APPLE_BUNDLE_ID") ?? "com.easysesh.app";
    const secret = await clientSecret(clientId);
    if (!secret) return false;
    const tokenResponse = await fetch("https://appleid.apple.com/auth/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ client_id: clientId, client_secret: secret, code: authorizationCode, grant_type: "authorization_code" }),
    });
    const tokens = await tokenResponse.json();
    const token = tokens.refresh_token ?? tokens.access_token;
    if (!token) {
      console.error("apple token exchange failed", tokens.error);
      return false;
    }
    const revoke = await fetch("https://appleid.apple.com/auth/revoke", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId, client_secret: secret, token,
        token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token",
      }),
    });
    return revoke.ok;
  } catch (error) {
    console.error("apple revoke failed", error);
    return false;
  }
}
