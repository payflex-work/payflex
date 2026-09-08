import { ExecutionContext, ForbiddenException } from '@nestjs/common';
import { AdminGuard } from './admin.guard';
import { PrismaService } from '../prisma/prisma.service';

describe('AdminGuard', () => {
  function buildContext(user?: { appUserId: string }): ExecutionContext {
    const request = { user };
    return {
      switchToHttp: () => ({ getRequest: () => request }),
    } as unknown as ExecutionContext;
  }

  it('rejects when there is no authenticated user on the request at all', async () => {
    const prisma = { appUser: { findUnique: jest.fn() } } as unknown as PrismaService;
    const guard = new AdminGuard(prisma);

    await expect(guard.canActivate(buildContext(undefined))).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('rejects an authenticated user who is not flagged isAdmin', async () => {
    const prisma = {
      appUser: { findUnique: jest.fn().mockResolvedValue({ id: 'user-1', isAdmin: false }) },
    } as unknown as PrismaService;
    const guard = new AdminGuard(prisma);

    await expect(guard.canActivate(buildContext({ appUserId: 'user-1' }))).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('rejects when the user record cannot be found at all', async () => {
    const prisma = {
      appUser: { findUnique: jest.fn().mockResolvedValue(null) },
    } as unknown as PrismaService;
    const guard = new AdminGuard(prisma);

    await expect(guard.canActivate(buildContext({ appUserId: 'ghost' }))).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('allows a user flagged isAdmin through', async () => {
    const prisma = {
      appUser: { findUnique: jest.fn().mockResolvedValue({ id: 'admin-1', isAdmin: true }) },
    } as unknown as PrismaService;
    const guard = new AdminGuard(prisma);

    await expect(guard.canActivate(buildContext({ appUserId: 'admin-1' }))).resolves.toBe(true);
  });
});
