import * as os from "os";
import * as crypto from "crypto";

export function generateToken(): string {
  return crypto.randomBytes(24).toString("base64url");
}

export function getLanAddresses(): string[] {
  const nets = os.networkInterfaces();
  const addrs: string[] = [];
  for (const entries of Object.values(nets)) {
    if (!entries) continue;
    for (const e of entries) {
      if (e.family === "IPv4" && !e.internal) {
        addrs.push(e.address);
      }
    }
  }
  return addrs;
}

export function preferredLanAddress(): string {
  const addrs = getLanAddresses();
  return addrs[0] ?? "127.0.0.1";
}
