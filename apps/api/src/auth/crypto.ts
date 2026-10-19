import crypto from 'node:crypto';

const SCRYPT_KEYLEN = 64;
const SCRYPT_COST = 16384;
const SCRYPT_BLOCK_SIZE = 8;
const SCRYPT_PARALLELIZATION = 1;

export const ACCESS_TOKEN_EXPIRES_IN_SECONDS = 900; // 15 menit (docs/08)
export const REFRESH_TOKEN_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 hari (docs/08)

export interface AccessTokenPayload {
  readonly sub: string;
  readonly email: string;
  readonly display_name: string;
  readonly iat: number;
  readonly exp: number;
}

function getJwtSecret(overrideSecret?: string): string {
  return (
    overrideSecret ??
    process.env['JWT_SECRET'] ??
    'jalur-rempah-dev-jwt-secret-key-minimum-32-bytes'
  );
}

export async function hashPassword(password: string): Promise<string> {
  const salt = crypto.randomBytes(16).toString('hex');
  const derivedKey = await new Promise<Buffer>((resolve, reject) => {
    crypto.scrypt(
      password,
      salt,
      SCRYPT_KEYLEN,
      {
        N: SCRYPT_COST,
        r: SCRYPT_BLOCK_SIZE,
        p: SCRYPT_PARALLELIZATION,
      },
      (err, key) => {
        if (err) reject(err);
        else resolve(key);
      },
    );
  });
  return `$scrypt$N=${SCRYPT_COST},r=${SCRYPT_BLOCK_SIZE},p=${SCRYPT_PARALLELIZATION}$${salt}$${derivedKey.toString('hex')}`;
}

export async function verifyPassword(
  password: string,
  storedHash: string,
): Promise<boolean> {
  const parts = storedHash.split('$');
  // Format: ['', 'scrypt', 'N=16384,r=8,p=1', '<salt>', '<hexHash>']
  if (parts.length !== 5 || parts[1] !== 'scrypt') {
    return false;
  }
  const salt = parts[3];
  const expectedHex = parts[4];
  if (!salt || !expectedHex) return false;

  const expectedBuf = Buffer.from(expectedHex, 'hex');
  const derivedKey = await new Promise<Buffer>((resolve, reject) => {
    crypto.scrypt(
      password,
      salt,
      expectedBuf.length,
      {
        N: SCRYPT_COST,
        r: SCRYPT_BLOCK_SIZE,
        p: SCRYPT_PARALLELIZATION,
      },
      (err, key) => {
        if (err) reject(err);
        else resolve(key);
      },
    );
  });

  if (derivedKey.length !== expectedBuf.length) {
    return false;
  }
  return crypto.timingSafeEqual(derivedKey, expectedBuf);
}

function base64UrlEncode(input: string | Buffer): string {
  return Buffer.from(input)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function base64UrlDecodeToString(input: string): string {
  const padLen = (4 - (input.length % 4)) % 4;
  const padded = input.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat(padLen);
  return Buffer.from(padded, 'base64').toString('utf8');
}

export function signAccessToken(
  user: { sub: string; email: string; display_name: string },
  options?: { secret?: string; expiresInSeconds?: number; nowMs?: number },
): string {
  const secret = getJwtSecret(options?.secret);
  const nowSec = Math.floor((options?.nowMs ?? Date.now()) / 1000);
  const expSec =
    nowSec + (options?.expiresInSeconds ?? ACCESS_TOKEN_EXPIRES_IN_SECONDS);

  const header = base64UrlEncode(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const payload = base64UrlEncode(
    JSON.stringify({
      sub: user.sub,
      email: user.email,
      display_name: user.display_name,
      iat: nowSec,
      exp: expSec,
    } satisfies AccessTokenPayload),
  );

  const signingInput = `${header}.${payload}`;
  const sig = crypto
    .createHmac('sha256', secret)
    .update(signingInput)
    .digest();
  return `${signingInput}.${base64UrlEncode(sig)}`;
}

export function verifyAccessToken(
  token: string,
  options?: { secret?: string; nowMs?: number },
): AccessTokenPayload | null {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const [headerB64, payloadB64, sigB64] = parts;
  if (!headerB64 || !payloadB64 || !sigB64) return null;

  const secret = getJwtSecret(options?.secret);
  const signingInput = `${headerB64}.${payloadB64}`;
  const expectedSig = base64UrlEncode(
    crypto.createHmac('sha256', secret).update(signingInput).digest(),
  );

  const sigBuf = Buffer.from(sigB64);
  const expBuf = Buffer.from(expectedSig);
  if (sigBuf.length !== expBuf.length) return null;
  if (!crypto.timingSafeEqual(sigBuf, expBuf)) return null;

  try {
    const decoded = JSON.parse(
      base64UrlDecodeToString(payloadB64),
    ) as AccessTokenPayload;
    const nowSec = Math.floor((options?.nowMs ?? Date.now()) / 1000);
    if (typeof decoded.exp !== 'number' || decoded.exp <= nowSec) {
      return null;
    }
    if (
      typeof decoded.sub !== 'string' ||
      typeof decoded.email !== 'string' ||
      typeof decoded.display_name !== 'string'
    ) {
      return null;
    }
    return decoded;
  } catch {
    return null;
  }
}

export function hashRefreshToken(rawToken: string): string {
  return crypto.createHash('sha256').update(rawToken).digest('hex');
}

export function generateRefreshToken(): {
  rawToken: string;
  tokenHash: string;
} {
  const rawToken = crypto.randomBytes(32).toString('base64url');
  const tokenHash = hashRefreshToken(rawToken);
  return { rawToken, tokenHash };
}
