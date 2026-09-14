import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Request } from 'express';
import { TokenService } from '../token/token.service';
import { IS_PUBLIC_KEY } from './public.decorator';

/**
 * Global guard (see AppModule's APP_GUARD provider) — authenticated by
 * default, routes opt out via @Public(). Two things happen here:
 *
 *  1. Authentication: verifies the Bearer token, attaches
 *     `request.user = { appUserId, stellarPublicKey }`.
 *  2. Ownership: for any route shaped `/users/:id/...` (the overwhelming
 *     majority of this API), the token's own appUserId must match the
 *     `:id` in the URL — a valid token for user A can never act as user
 *     B just by changing the URL. Routes without a `:id` param (PayTag
 *     resolution, claim previews, admin triggers, etc.) skip this check;
 *     see each controller for whether that route is meant to be public
 *     instead (marked with @Public()) or just not owner-scoped.
 *
 * Bootstrap tokens (see TokenService) are accepted ONLY on
 * `PATCH /users/:id/stellar-public-key` — the one call that has to happen
 * before a real login is even possible, since login proves ownership of
 * the on-device key by verifying a signature against the registered
 * public key, and there is no key registered yet at that point.
 * Residual risk accepted here: a bootstrap token is a bearer credential
 * for that one endpoint for up to 10 minutes after account creation, so
 * if it leaks in that narrow window before the real login happens, it
 * could be used to set the registered public key once. After that, keys
 * are immutable (see UsersService.setStellarPublicKey), so the account
 * stays under the control of whoever holds the device keypair.
 */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly tokens: TokenService,
  ) {}

  canActivate(context: ExecutionContext): boolean {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const request = context.switchToHttp().getRequest<Request>();
    const token = this.extractBearerToken(request);
    if (!token) throw new UnauthorizedException('Missing bearer token.');

    const payload = this.tokens.verify(token);

    if (payload.scope === 'bootstrap') {
      const routePath = request.route?.path as string | undefined;
      const isPublicKeyRoute = request.method === 'PATCH' && routePath === '/users/:id/stellar-public-key';
      if (!isPublicKeyRoute || request.params.id !== payload.sub) {
        throw new ForbiddenException('This token can only be used to register a Stellar public key, once.');
      }
      (request as Request & { user: { appUserId: string } }).user = { appUserId: payload.sub };
      return true;
    }

    if (payload.scope !== 'access') {
      throw new UnauthorizedException('This token cannot be used to call the API directly.');
    }

    (request as Request & { user: { appUserId: string; stellarPublicKey?: string } }).user = {
      appUserId: payload.sub,
      stellarPublicKey: payload.stellarPublicKey,
    };

    if (request.params.id && request.params.id !== payload.sub) {
      throw new ForbiddenException("You can't act on another user's account.");
    }

    return true;
  }

  private extractBearerToken(request: Request): string | undefined {
    const header = request.headers.authorization;
    if (!header?.startsWith('Bearer ')) return undefined;
    return header.slice('Bearer '.length);
  }
}
