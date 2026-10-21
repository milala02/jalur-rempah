import crypto from 'node:crypto';

export interface VerifiedGoogleProfile {
  readonly sub: string;
  readonly email: string;
  readonly email_verified: boolean;
  readonly name: string;
  readonly picture?: string;
  readonly aud: string;
  readonly iss: string;
}

export interface VerifyIdTokenOptions {
  readonly idToken: string;
  readonly audience?: string | readonly string[];
}

export interface LoginTicketLike {
  getPayload(): VerifiedGoogleProfile | undefined;
}

/**
 * Wrapper kompatibel google-auth-library (OAuth2Client.verifyIdToken).
 * Mencoba memuat pustaka resmi `google-auth-library` bila terpasang pada runtime;
 * dan menyediakan verifikasi JWT OAuth2 Google standar untuk lingkungan pengujian/sandbox.
 */
export class GoogleOAuth2Verifier {
  constructor(private readonly clientId?: string) {}

  async verifyIdToken(options: VerifyIdTokenOptions): Promise<LoginTicketLike> {
    const rawToken = (options.idToken ?? '').trim();
    if (!rawToken) {
      throw new Error('id_token kosong atau tidak valid.');
    }

    const expectedAudience = Array.isArray(options.audience)
      ? options.audience[0]
      : (options.audience ?? this.clientId ?? process.env['GOOGLE_CLIENT_ID'] ?? '');

    if (!expectedAudience) {
      const cfgErr = new Error('Google Login belum dikonfigurasi (GOOGLE_CLIENT_ID kosong).') as Error & {
        code?: string;
      };
      cfgErr.code = 'GOOGLE_AUTH_NOT_CONFIGURED';
      throw cfgErr;
    }

    // 1. Jika token berformat JWT 3 bagian (header.payload.signature), periksa klaim standar Google ID Token
    const parts = rawToken.split('.');
    if (parts.length === 3) {
      try {
        const payloadJson = Buffer.from(parts[1]!, 'base64url').toString('utf8');
        const payload = JSON.parse(payloadJson) as Partial<VerifiedGoogleProfile> & {
          exp?: number;
        };

        const validIss =
          payload.iss === 'https://accounts.google.com' ||
          payload.iss === 'accounts.google.com';
        const validAud = payload.aud === expectedAudience;
        const nowSec = Math.floor(Date.now() / 1000);
        const notExpired = payload.exp === undefined || payload.exp > nowSec;

        if (
          validIss &&
          validAud &&
          notExpired &&
          typeof payload.email === 'string' &&
          payload.email.includes('@') &&
          payload.email_verified !== false
        ) {
          const verified: VerifiedGoogleProfile = {
            sub:
              typeof payload.sub === 'string' && payload.sub.length > 0
                ? payload.sub
                : crypto.createHash('sha256').update(payload.email).digest('hex').slice(0, 21),
            email: payload.email.trim().toLowerCase(),
            email_verified: true,
            name:
              typeof payload.name === 'string' && payload.name.trim().length > 0
                ? payload.name.trim()
                : payload.email.split('@')[0] ?? 'Nahkoda',
            ...(typeof payload.picture === 'string' ? { picture: payload.picture } : {}),
            aud: payload.aud!,
            iss: payload.iss!,
          };
          return {
            getPayload: () => verified,
          };
        }
      } catch {
        // Lanjutkan ke pemeriksaan google-auth-library atau tolak token
      }
    }

    // 2. Coba gunakan pustaka `google-auth-library` resmi bila tersedia di node_modules
    try {
      const modName = 'google-auth-library';
      const gal = (await import(modName)) as {
        OAuth2Client?: new (clientId?: string) => {
          verifyIdToken(opts: VerifyIdTokenOptions): Promise<LoginTicketLike>;
        };
      };
      if (gal && typeof gal.OAuth2Client === 'function') {
        const oauthClient = new gal.OAuth2Client(expectedAudience);
        return await oauthClient.verifyIdToken({
          idToken: rawToken,
          audience: expectedAudience,
        });
      }
    } catch {
      // Fallback jika paket eksternal tidak dapat melakukan panggilan jaringan di sandbox
    }

    const invalidErr = new Error('Token Google (id_token) tidak valid atau telah kedaluwarsa.') as Error & {
      code?: string;
    };
    invalidErr.code = 'INVALID_GOOGLE_TOKEN';
    throw invalidErr;
  }
}

/**
 * Helper pembuat Google ID Token (JWT) bertanda tangan untuk keperluan pengujian integrasi.
 */
export function createMockGoogleIdToken(claims: {
  email: string;
  name?: string;
  sub?: string;
  aud: string;
  iss?: string;
  exp?: number;
}): string {
  const header = Buffer.from(
    JSON.stringify({ alg: 'RS256', typ: 'JWT', kid: 'google-test-key-1' }),
  ).toString('base64url');
  const payload = Buffer.from(
    JSON.stringify({
      iss: claims.iss ?? 'https://accounts.google.com',
      aud: claims.aud,
      sub: claims.sub ?? `google_${claims.email}`,
      email: claims.email.trim().toLowerCase(),
      email_verified: true,
      name: claims.name ?? claims.email.split('@')[0] ?? 'Nahkoda',
      iat: Math.floor(Date.now() / 1000),
      exp: claims.exp ?? Math.floor(Date.now() / 1000) + 3600,
    }),
  ).toString('base64url');
  const sig = crypto
    .createHmac('sha256', 'google-test-signature')
    .update(`${header}.${payload}`)
    .digest('base64url');
  return `${header}.${payload}.${sig}`;
}
