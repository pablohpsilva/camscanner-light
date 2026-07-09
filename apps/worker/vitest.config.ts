import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";
export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        wrangler: { configPath: "./wrangler.toml" },
        miniflare: {
          bindings: {
            PLAY_SA_CLIENT_EMAIL: "test-sa@test.iam.gserviceaccount.com",
            PLAY_PACKAGE_NAME: "com.example.test",
            PLAY_SA_PRIVATE_KEY: "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDgW5ww8563wCMG\nvYnv/LqKf/BJljoAF6nj3KMLcvqalZDUqUBIXh5pj/l+EMR014hp074hsjiCum7x\nBihSHImi/TfFOmjv29vl3SVn1f+mTAvYoAe0rT973SdQQBGmI3883pMAGt+1Zpi3\nmvvpKgsGgn8VaNGEx0U4uWOnmmp11kYpuhjeb12EkdksDIRv+qbQTrSFZ/BIZ3wX\nXyKQvEYntUL+YOYQvtAWsul/5+Y8zcoB3x3BYgLscR0/C6YJH8EorP4v3pBi2RO+\nklt8qTDYBi5nUu5G54ow+SZzjZQRRVwSVjUA8cYMD/QbU+r8brbeF+i2SRYP9hto\nTVM4106tAgMBAAECggEAHqqm+NHz+e3bW8qAljsXTGMcdxJ/rw+M+0ZnSuNWedbD\nyy2vSbUDty4kziSAle/4B28X6AcyTjwpeex7im24Kn0uKFlJiq+kqRDHUiAgJ5zx\naZTGON4NdWLPQtrfDrR/adSKh1MlDOiPK1mV4VML2sHvmP+Q0/Ng9NXyVzB2KND1\nld1hVrEddFpr5DOfxp6uEE5OYqR93n/eeJWP7PKrM6EtlrexNoNU0EfLTcqCsWqz\nPTQmtREAlovrlxhTjK70k8xiZCTBk/HutbOnCxq6dtYKqbuzJvFWAQQbZVe7fGmZ\n8w5Q0pQTK+5CzAMHoELrjnu1WW/83W1A6wFsirt0gQKBgQDwVx002EQzJE7pH5Nn\nWICv9jLv5svjUU0HszaB7pPzEwByN5e7Q/8gNXTGZ0vzuUa/206Qb1tW6hQvK9jQ\nl647SqLpCWstLCWrk8ZaO3TSPRsBx5916qDMZwgL9TRre1Mnjh+uiFtvRlVIiDUf\nY+LqqXyRkI1jhogbpjBVHkcyEQKBgQDu+eiHxdsHeBlSSAsIVlWmom2m/GB62OAg\n0Riqnv85sfzanDm1ZXP5nydJZvmN7AZ6WZCcmnNVqPUEZNG1PFTaF9p3cVlVIiOH\nCqpDBOlzbBf/pheU3NzOEXC4X4JYE/Fzp5WxXo5JgxoZa4QzH/1BvAeKcL2EixV0\nhQ+wMjm23QKBgEyZ910YcOQ79kqnHbwaoSl0Ntfvn5xcFUkW/ZB8EfuvWr0Mqves\nvGvvncB+u956duo/Y9L1Kw+Qm85NE1WogoezSiksL1S+dWMyPk4UFS/M+gafMVvL\n5GRBknb9OC/ppp881SwzmbDlodj0ULoog/J3ApUClY3bGxZ06YK3m8mBAoGBAIXJ\nnyaz3AV4dSSddJ+8RcM+WAkOba0Y0ZFNvnN3BAf230o8AArPu3faZBIx9jBAHPhO\nQCmMRlmEd3d4QfcmyZI3nHUWHh8NN7qYe+19SHz33Q+gmr8aTvuGxAZUYhKRR7Gp\n9qIP/7SkEu58RMyichRlAgu9Rjx36REMlVXdKHZ5AoGAe16AQOlAW5nU4sM6iqjJ\nZjGQxZIb6gEqf1wIUlY/xBf+jbV5Xh0t+ujhAsdnAbg8iuQFjjKSOtaHRfUJw65h\nd2efpVReyVU0B6pD2jzvgmppt5eBO4MaEPM6j6KR+PVCw0e8LKfnCAMDkpMHsusn\nJWbVCUax4zv6oT0ibP6u6KU=\n-----END PRIVATE KEY-----\n",
            GITHUB_APP_PRIVATE_KEY: "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDgW5ww8563wCMG\nvYnv/LqKf/BJljoAF6nj3KMLcvqalZDUqUBIXh5pj/l+EMR014hp074hsjiCum7x\nBihSHImi/TfFOmjv29vl3SVn1f+mTAvYoAe0rT973SdQQBGmI3883pMAGt+1Zpi3\nmvvpKgsGgn8VaNGEx0U4uWOnmmp11kYpuhjeb12EkdksDIRv+qbQTrSFZ/BIZ3wX\nXyKQvEYntUL+YOYQvtAWsul/5+Y8zcoB3x3BYgLscR0/C6YJH8EorP4v3pBi2RO+\nklt8qTDYBi5nUu5G54ow+SZzjZQRRVwSVjUA8cYMD/QbU+r8brbeF+i2SRYP9hto\nTVM4106tAgMBAAECggEAHqqm+NHz+e3bW8qAljsXTGMcdxJ/rw+M+0ZnSuNWedbD\nyy2vSbUDty4kziSAle/4B28X6AcyTjwpeex7im24Kn0uKFlJiq+kqRDHUiAgJ5zx\naZTGON4NdWLPQtrfDrR/adSKh1MlDOiPK1mV4VML2sHvmP+Q0/Ng9NXyVzB2KND1\nld1hVrEddFpr5DOfxp6uEE5OYqR93n/eeJWP7PKrM6EtlrexNoNU0EfLTcqCsWqz\nPTQmtREAlovrlxhTjK70k8xiZCTBk/HutbOnCxq6dtYKqbuzJvFWAQQbZVe7fGmZ\n8w5Q0pQTK+5CzAMHoELrjnu1WW/83W1A6wFsirt0gQKBgQDwVx002EQzJE7pH5Nn\nWICv9jLv5svjUU0HszaB7pPzEwByN5e7Q/8gNXTGZ0vzuUa/206Qb1tW6hQvK9jQ\nl647SqLpCWstLCWrk8ZaO3TSPRsBx5916qDMZwgL9TRre1Mnjh+uiFtvRlVIiDUf\nY+LqqXyRkI1jhogbpjBVHkcyEQKBgQDu+eiHxdsHeBlSSAsIVlWmom2m/GB62OAg\n0Riqnv85sfzanDm1ZXP5nydJZvmN7AZ6WZCcmnNVqPUEZNG1PFTaF9p3cVlVIiOH\nCqpDBOlzbBf/pheU3NzOEXC4X4JYE/Fzp5WxXo5JgxoZa4QzH/1BvAeKcL2EixV0\nhQ+wMjm23QKBgEyZ910YcOQ79kqnHbwaoSl0Ntfvn5xcFUkW/ZB8EfuvWr0Mqves\nvGvvncB+u956duo/Y9L1Kw+Qm85NE1WogoezSiksL1S+dWMyPk4UFS/M+gafMVvL\n5GRBknb9OC/ppp881SwzmbDlodj0ULoog/J3ApUClY3bGxZ06YK3m8mBAoGBAIXJ\nnyaz3AV4dSSddJ+8RcM+WAkOba0Y0ZFNvnN3BAf230o8AArPu3faZBIx9jBAHPhO\nQCmMRlmEd3d4QfcmyZI3nHUWHh8NN7qYe+19SHz33Q+gmr8aTvuGxAZUYhKRR7Gp\n9qIP/7SkEu58RMyichRlAgu9Rjx36REMlVXdKHZ5AoGAe16AQOlAW5nU4sM6iqjJ\nZjGQxZIb6gEqf1wIUlY/xBf+jbV5Xh0t+ujhAsdnAbg8iuQFjjKSOtaHRfUJw65h\nd2efpVReyVU0B6pD2jzvgmppt5eBO4MaEPM6j6KR+PVCw0e8LKfnCAMDkpMHsusn\nJWbVCUax4zv6oT0ibP6u6KU=\n-----END PRIVATE KEY-----\n",
            GITHUB_APP_ID: "123456",
            GITHUB_APP_INSTALLATION_ID: "12345",
            TURNSTILE_SECRET: "test-turnstile-secret",
          },
        },
      },
    },
  },
});
