import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Request } from 'express';
import { PrismaService } from '../prisma/prisma.service';

/**
 * Runs after the global AuthGuard, so `request.user.appUserId` is always
 * a verified identity by the time this executes — this only adds the
 * extra check that the identity is actually flagged isAdmin. Unlike
 * AgentService.setAgentStatus (self-service), there is no public way to
 * become an admin — see AppUser.isAdmin's doc comment in schema.prisma.
 */
@Injectable()
export class AdminGuard implements CanActivate {
  constructor(private readonly prisma: PrismaService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<Request>();
    const appUserId = (request as Request & { user?: { appUserId: string } }).user?.appUserId;
    if (!appUserId) throw new ForbiddenException('Admin access required.');

    const user = await this.prisma.appUser.findUnique({ where: { id: appUserId } });
    if (!user?.isAdmin) throw new ForbiddenException('Admin access required.');

    return true;
  }
}
