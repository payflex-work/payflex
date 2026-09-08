/**
 * One-time, out-of-band bootstrap for the first admin — there is
 * deliberately no public endpoint that can create an admin (see
 * AppUser.isAdmin's doc comment in schema.prisma and AdminGuard). Every
 * admin after the first is created by an existing admin via
 * POST /admin/users/:targetAppUserId/admin-status.
 *
 * Run with: npm run provision:admin -- <phoneNumber-or-appUserId>
 */
import { NestFactory } from '@nestjs/core';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/prisma/prisma.service';

async function main() {
  const identifier = process.argv[2];
  if (!identifier) {
    console.error('Usage: npm run provision:admin -- <phoneNumber-or-appUserId>');
    process.exit(1);
  }

  const app = await NestFactory.createApplicationContext(AppModule);

  try {
    const prisma = app.get(PrismaService);
    const user = await prisma.appUser.findFirst({
      where: { OR: [{ id: identifier }, { phoneNumber: identifier }] },
    });
    if (!user) {
      console.error(`No AppUser found matching "${identifier}" (checked id and phoneNumber).`);
      process.exit(1);
    }

    const updated = await prisma.appUser.update({
      where: { id: user.id },
      data: { isAdmin: true },
    });
    console.log('✅ Granted admin access:', {
      id: updated.id,
      phoneNumber: updated.phoneNumber,
      firstName: updated.firstName,
      lastName: updated.lastName,
    });
  } finally {
    await app.close();
  }
}

main().catch((err) => {
  console.error('\n❌ Admin provisioning failed:', err);
  process.exit(1);
});
