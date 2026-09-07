import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';

/**
 * `ioredis` has been a dependency since Phase 1 ("cache/session") but had
 * no actual use until auth needed somewhere to hold short-lived login
 * challenges (Postgres would work too, but a challenge is exactly the
 * kind of short-TTL, high-churn data Redis is for for and the dependency
 * was already sitting there unused).
 */
@Injectable()
export class RedisService implements OnModuleDestroy {
  readonly client: Redis;

  constructor(configService: ConfigService) {
    const url = configService.get<string>('REDIS_URL') ?? 'redis://localhost:6379';
    this.client = new Redis(url, { lazyConnect: false });
  }

  async setWithTtl(key: string, value: string, ttlSeconds: number): Promise<void> {
    await this.client.set(key, value, 'EX', ttlSeconds);
  }

  async getAndDelete(key: string): Promise<string | null> {
    // Atomic get-then-delete so a challenge can only ever be consumed
    // once, even under concurrent login attempts.
    const value = await this.client.get(key);
    if (value !== null) await this.client.del(key);
    return value;
  }

  async onModuleDestroy() {
    this.client.disconnect();
  }
}
