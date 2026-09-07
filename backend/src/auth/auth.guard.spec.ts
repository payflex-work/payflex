import { ExecutionContext, ForbiddenException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Reflector } from '@nestjs/core';
import { AuthGuard } from './auth.guard';
import { TokenService } from '../token/token.service';

/**
 * TokenService is instantiated with a real JwtService rather than mocked —
 * signing/verifying real JWTs is fast and deterministic, and exercising
 * the guard against tokens it can't distinguish from production ones is
 * worth more than asserting on a mocked `verify()` call.
 */
function buildTokens() {
  return new TokenService(new JwtService({ secret: 'test-secret' }));
}

function buildContext(opts: {
  isPublic?: boolean;
  authorization?: string;
  routePath?: string;
  method?: string;
  params?: Record<string, string>;
}): { context: ExecutionContext; request: Record<string, unknown> } {
  const request: Record<string, unknown> = {
    headers: opts.authorization ? { authorization: opts.authorization } : {},
    route: opts.routePath ? { path: opts.routePath } : undefined,
    method: opts.method ?? 'GET',
    params: opts.params ?? {},
  };
  const context = {
    getHandler: () => ({}),
    getClass: () => ({}),
    switchToHttp: () => ({ getRequest: () => request }),
  } as unknown as ExecutionContext;
  return { context, request };
}

function buildGuard(tokens: TokenService, isPublic: boolean) {
  const reflector = {
    getAllAndOverride: jest.fn().mockReturnValue(isPublic),
  } as unknown as Reflector;
  return new AuthGuard(reflector, tokens);
}

describe('AuthGuard', () => {
  it('allows a @Public() route through with no token at all', () => {
    const guard = buildGuard(buildTokens(), true);
    const { context } = buildContext({});
    expect(guard.canActivate(context)).toBe(true);
  });

  it('rejects a protected route with no Authorization header', () => {
    const guard = buildGuard(buildTokens(), false);
    const { context } = buildContext({});
    expect(() => guard.canActivate(context)).toThrow(UnauthorizedException);
  });

  it('rejects a header that is not a Bearer token', () => {
    const guard = buildGuard(buildTokens(), false);
    const { context } = buildContext({ authorization: 'Basic abc123' });
    expect(() => guard.canActivate(context)).toThrow(UnauthorizedException);
  });

  it('rejects an unparseable/expired token', () => {
    const guard = buildGuard(buildTokens(), false);
    const { context } = buildContext({ authorization: 'Bearer not-a-real-jwt' });
    expect(() => guard.canActivate(context)).toThrow(UnauthorizedException);
  });

  it('accepts a valid access token on a route with no :id param', () => {
    const tokens = buildTokens();
    const guard = buildGuard(tokens, false);
    const accessToken = tokens.signAccessToken('user-1', 'bmoni-1');
    const { context, request } = buildContext({ authorization: `Bearer ${accessToken}` });

    expect(guard.canActivate(context)).toBe(true);
    expect(request.user).toEqual({ appUserId: 'user-1', bmoniUserId: 'bmoni-1' });
  });

  it('accepts a valid access token when :id matches the token subject', () => {
    const tokens = buildTokens();
    const guard = buildGuard(tokens, false);
    const accessToken = tokens.signAccessToken('user-1', 'bmoni-1');
    const { context } = buildContext({
      authorization: `Bearer ${accessToken}`,
      params: { id: 'user-1' },
    });

    expect(guard.canActivate(context)).toBe(true);
  });

  it("rejects a valid access token when :id belongs to a different user (cross-user ownership)", () => {
    const tokens = buildTokens();
    const guard = buildGuard(tokens, false);
    const accessToken = tokens.signAccessToken('user-1', 'bmoni-1');
    const { context } = buildContext({
      authorization: `Bearer ${accessToken}`,
      params: { id: 'user-2' },
    });

    expect(() => guard.canActivate(context)).toThrow(ForbiddenException);
  });

  it('rejects a refresh-scope token used directly against a protected route', () => {
    const tokens = buildTokens();
    const guard = buildGuard(tokens, false);
    const { token: refreshToken } = tokens.signRefreshToken('user-1');
    const { context } = buildContext({ authorization: `Bearer ${refreshToken}` });

    expect(() => guard.canActivate(context)).toThrow(UnauthorizedException);
  });

  describe('bootstrap-scoped tokens', () => {
    it('accepts a bootstrap token on exactly PATCH /users/:id/owner-address for its own subject', () => {
      const tokens = buildTokens();
      const guard = buildGuard(tokens, false);
      const bootstrapToken = tokens.signBootstrapToken('user-1');
      const { context, request } = buildContext({
        authorization: `Bearer ${bootstrapToken}`,
        method: 'PATCH',
        routePath: '/users/:id/owner-address',
        params: { id: 'user-1' },
      });

      expect(guard.canActivate(context)).toBe(true);
      expect(request.user).toEqual({ appUserId: 'user-1' });
    });

    it('rejects a bootstrap token on any other route', () => {
      const tokens = buildTokens();
      const guard = buildGuard(tokens, false);
      const bootstrapToken = tokens.signBootstrapToken('user-1');
      const { context } = buildContext({
        authorization: `Bearer ${bootstrapToken}`,
        method: 'GET',
        routePath: '/users/:id',
        params: { id: 'user-1' },
      });

      expect(() => guard.canActivate(context)).toThrow(ForbiddenException);
    });

    it('rejects a bootstrap token on the owner-address route for a different user', () => {
      const tokens = buildTokens();
      const guard = buildGuard(tokens, false);
      const bootstrapToken = tokens.signBootstrapToken('user-1');
      const { context } = buildContext({
        authorization: `Bearer ${bootstrapToken}`,
        method: 'PATCH',
        routePath: '/users/:id/owner-address',
        params: { id: 'user-2' },
      });

      expect(() => guard.canActivate(context)).toThrow(ForbiddenException);
    });
  });
});
