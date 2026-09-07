import { SetMetadata } from '@nestjs/common';

export const IS_PUBLIC_KEY = 'isPublic';

/**
 * Marks a route as reachable without a Bearer token. Everything else is
 * authenticated-by-default (see AuthGuard) — a route has to opt out
 * explicitly, not the other way around, so a new controller added later
 * doesn't accidentally end up open.
 */
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
