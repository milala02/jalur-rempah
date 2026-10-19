// Skrip Uji Muat (k6 / Load Test) untuk 100-500 Pemain (M6 — docs/10 & docs/13)
// Jalankan dengan: k6 run scripts/load-test.mjs (atau BASE_URL=https://domain/v1 k6 run scripts/load-test.mjs)
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 100 },
    { duration: '1m', target: 250 },
    { duration: '30s', target: 500 },
    { duration: '20s', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<300'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:3100/v1';

export default function () {
  const worldRes = http.get(`${BASE_URL}/world`, {
    headers: { 'X-Client-Version': '0.1.0' },
  });
  check(worldRes, {
    'GET /world 200': (r) => r.status === 200,
    'header X-Tick ada': (r) => r.headers['X-Tick'] !== undefined,
  });

  const marketRes = http.get(`${BASE_URL}/world/market/banda`);
  check(marketRes, {
    'GET /world/market/banda 200': (r) => r.status === 200,
  });

  const lbRes = http.get(`${BASE_URL}/leaderboard?limit=50`);
  check(lbRes, {
    'GET /leaderboard 200': (r) => r.status === 200,
  });

  sleep(1);
}
