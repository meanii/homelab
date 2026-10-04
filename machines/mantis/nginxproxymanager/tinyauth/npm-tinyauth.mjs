// Puts tinyauth (forward auth) in front of NPM proxy hosts and creates the
// login host. Runs inside the NPM container (CT 107) from /app:
//   docker exec -w /app root-nginxproxymanager-1 node npm-tinyauth.mjs <domain>...
// With no arguments it only creates auth.home.aniicrite.dev.
// The admin token is signed with NPM's own key and expires after 5 minutes.
import jwt from "jsonwebtoken"; import crypto from "node:crypto"; import Database from "better-sqlite3";
import { getPrivateKey } from "/app/lib/config.js";

const AUTH_HOST = "auth.home.aniicrite.dev";
const CERT = 23; // wildcard *.home / *.ghost certificate
// NPM's own `location /` is replaced by this one (NPM skips its default when the
// advanced config defines `location /`), so the proxy and websocket headers are
// repeated here. tinyauth answers 401 with the login URL in x-tinyauth-location.
const ADVANCED = `location / {
  include conf.d/include/proxy.conf;
  proxy_http_version 1.1;
  proxy_set_header Upgrade $http_upgrade;
  proxy_set_header Connection $http_connection;
  auth_request /tinyauth;
  auth_request_set $redirection_url $upstream_http_x_tinyauth_location;
  error_page 401 403 =302 $redirection_url;
}
location /tinyauth {
  internal;
  proxy_pass http://tinyauth:3000/api/auth/nginx;
  proxy_pass_request_body off;
  proxy_set_header content-length "";
  proxy_set_header x-original-url $scheme://$http_host$request_uri;
  proxy_set_header x-original-method $request_method;
  proxy_set_header x-forwarded-for $proxy_add_x_forwarded_for;
  proxy_set_header x-real-ip $remote_addr;
}`;

const db = new Database("/data/database.sqlite", { readonly: true });
const admin = db.prepare("SELECT id FROM user WHERE is_deleted = 0 AND roles LIKE '%admin%' ORDER BY id LIMIT 1").get(); db.close();
const session = jwt.sign({ attrs: { id: admin.id }, scope: ["user"], jti: crypto.randomBytes(12).toString("base64") }, getPrivateKey(), { algorithm: "RS256", expiresIn: "5m" });
const api = (p, o = {}) => fetch("http://127.0.0.1:81/api" + p, { ...o, headers: { Authorization: `Bearer ${session}`, "Content-Type": "application/json" } })
  .then(async r => { const b = await r.json(); if (!r.ok) throw new Error(`${p}: ${JSON.stringify(b)}`); return b; });

const hosts = await api("/nginx/proxy-hosts");
if (!hosts.some(h => h.domain_names.includes(AUTH_HOST))) {
  const h = await api("/nginx/proxy-hosts", { method: "POST", body: JSON.stringify({
    domain_names: [AUTH_HOST], forward_scheme: "http", forward_host: "tinyauth", forward_port: 3000,
    certificate_id: CERT, ssl_forced: true, block_exploits: true, allow_websocket_upgrade: true, http2_support: false,
    access_list_id: 0, advanced_config: "", locations: [], meta: {} }) });
  console.log("created", AUTH_HOST, "id", h.id);
}
for (const domain of process.argv.slice(2)) {
  const h = hosts.find(x => x.domain_names.includes(domain));
  if (!h) { console.log("no host for", domain); continue; }
  await api(`/nginx/proxy-hosts/${h.id}`, { method: "PUT", body: JSON.stringify({ advanced_config: ADVANCED, access_list_id: 0 }) });
  console.log("protected", domain, "id", h.id, "->", `${h.forward_scheme}://${h.forward_host}:${h.forward_port}`);
}
