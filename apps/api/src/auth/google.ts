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
 * Verifikasi token HANYA lewat pustaka resmi `google-auth-library`.
 * Tidak ada fallback decode-manual — jika library tidak tersedia, lempar error.
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

    // Verifikasi HANYA melalui google-auth-library resmi (termasuk verifikasi tanda tangan)
    try {
      const modName = 'google-auth-library';
      const gal = (await import(modName)) as {
        OAuth2Client?: new (clientId?: string) => {
          verifyIdToken(opts: VerifyIdTokenOptions): Promise<LoginTicketLike>;
        };
      };
      if (gal && typeof gal.OAuth2Client === 'function') {
        const oauthClient = new gal.OAuth2Client(expectedAudience);
        const ticket = await oauthClient.verifyIdToken({
          idToken: rawToken,
          audience: expectedAudience,
        });

        // Pastikan email_verified === true (bukan sekadar !== false)
        const payload = ticket.getPayload();
        if (!payload || payload.email_verified !== true) {
          const unverifiedErr = new Error(
            'Email pada akun Google belum diverifikasi.',
          ) as Error & { code?: string };
          unverifiedErr.code = 'INVALID_GOOGLE_TOKEN';
          throw unverifiedErr;
        }

        return ticket;
      }
    } catch (err) {
      // Jika error berasal dari pengecekan email_verified di atas, re-throw
      if ((err as { code?: string }).code === 'INVALID_GOOGLE_TOKEN') {
        throw err;
      }
      // Library gagal memverifikasi tanda tangan / jaringan → tolak token
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
