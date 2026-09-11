import { Controller, Get } from '@nestjs/common';
import { Public } from '../auth/public.decorator';
import { PrismaService } from '../prisma/prisma.service';

@Controller('v1')
export class HealthController {
  constructor(private readonly prisma: PrismaService) {}

  @Public()
  @Get('health')
  async health() {
    await this.prisma.$queryRaw`SELECT 1`;
    return { status: 'ok' };
  }
}
