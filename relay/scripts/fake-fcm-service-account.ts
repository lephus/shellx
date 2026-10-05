// Local testing only: writes a throwaway Firebase service account key (fresh RSA key, fake project
// "shellx-local") to the path given, for running the relay against a fake FCM server
// (FCM_ENDPOINT / FCM_TOKEN_ENDPOINT, loopback URLs only). Google would refuse this key.
//   npm run fake-fcm-account -- .data/fake-fcm.json
import { generateKeyPairSync } from "node:crypto";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

const path = process.argv[2];
if (path === undefined) {
  console.error("usage: npm run fake-fcm-account -- <path>");
  process.exit(1);
}
const { privateKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  privateKeyEncoding: { type: "pkcs8", format: "pem" },
  publicKeyEncoding: { type: "spki", format: "pem" },
});
mkdirSync(dirname(path), { recursive: true });
writeFileSync(
  path,
  JSON.stringify({
    type: "service_account",
    project_id: "shellx-local",
    private_key: privateKey,
    client_email: "fake@shellx-local.iam.gserviceaccount.com",
    token_uri: "https://oauth2.googleapis.com/token",
  }),
  { mode: 0o600 },
);
console.log(path);
