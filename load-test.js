import http from 'k6/http';
import { sleep, check } from 'k6';

// ==============================================================================
// MOYEOLOG k6 Load Testing Scenario Config
// ==============================================================================

export const options = {
  stages: [
    { duration: '15s', target: 10 }, // Ramp-up: 0 to 10 virtual users in 15s
    { duration: '30s', target: 20 }, // Stress: Sustain 20 virtual users for 30s
    { duration: '15s', target: 0 },  // Ramp-down: Cool down back to 0 users
  ],
  thresholds: {
    // We expect the HTTP error rate to be low (excluding 429 Rate Limit responses)
    http_req_failed: ['rate<0.05'], 
    // 95% of requests should complete within 1.5 seconds
    http_req_duration: ['p(95)<1500'], 
  },
};

const TARGET_URL = 'https://moyeolog.kro.kr';

export default function () {
  // Scenario 1: Hit Frontend UI Home page
  const homeRes = http.get(`${TARGET_URL}/`);
  check(homeRes, {
    'Home status is 200': (r) => r.status === 200,
  });
  sleep(1); // Wait 1 second (think time)

  // Scenario 2: Hit Backend API Endpoint
  const apiRes = http.get(`${TARGET_URL}/api/search-image?query=coffee`);
  check(apiRes, {
    // 429 is an expected response if Rate Limiting kicks in under load
    'API status is 200 or 429': (r) => r.status === 200 || r.status === 429,
  });
  sleep(1); // Wait 1 second
}
