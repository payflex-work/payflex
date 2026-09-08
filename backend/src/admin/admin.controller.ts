import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { AdminGuard } from './admin.guard';
import { AdminService } from './admin.service';
import { SetAdminStatusDto } from './dto/set-admin-status.dto';

/**
 * Every route here is AdminGuard-protected (not the usual
 * /users/:id/... ownership shape, since these actions target *other*
 * users, not the caller — see AdminGuard's doc comment).
 */
@Controller('admin')
@UseGuards(AdminGuard)
export class AdminController {
  constructor(private readonly admin: AdminService) {}

  @Get('stats')
  getStats() {
    return this.admin.getStats();
  }

  @Post('users/:targetAppUserId/admin-status')
  setAdminStatus(
    @Param('targetAppUserId') targetAppUserId: string,
    @Body() dto: SetAdminStatusDto,
  ) {
    return this.admin.setAdminStatus(targetAppUserId, dto.isAdmin);
  }
}
