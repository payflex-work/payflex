import {
  Controller,
  Get,
  Post,
  Put,
  Body,
  Param,
  Req,
  HttpCode,
  HttpStatus,
  UsePipes,
  ValidationPipe,
} from '@nestjs/common';
import { Request } from 'express';
import {
  SafeboxService,
  SafeboxRecord,
  SafeboxMemberRecord,
  SafeboxTxRecord,
} from './safebox.service';
import {
  CreateSafeboxDto,
  ContributeSafeboxDto,
  WithdrawSafeboxDto,
  UpdateMemberRoleDto,
  InitiateOwnershipTransferDto,
  ConfirmOwnershipTransferDto,
} from './dto/safebox.dto';

/**
 * Not `@Public()`, so the global AuthGuard (see auth/auth.guard.ts)
 * always either populates `request.user` from a verified access token or
 * rejects the request before any handler here runs — `req.user.appUserId`
 * is the caller's real, authenticated identity, never a value a client
 * can influence directly.
 */
@Controller('safebox')
@UsePipes(new ValidationPipe({ transform: true, whitelist: true }))
export class SafeboxController {
  constructor(private readonly safeboxService: SafeboxService) {}

  private getUserId(req: Request): string {
    return (req as Request & { user: { appUserId: string } }).user.appUserId;
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  async createSafebox(@Req() req: Request, @Body() dto: CreateSafeboxDto): Promise<SafeboxRecord> {
    return this.safeboxService.createSafebox(this.getUserId(req), dto);
  }

  @Get()
  async getUserSafeboxes(@Req() req: Request): Promise<{ safebox: SafeboxRecord; role: string }[]> {
    return this.safeboxService.getUserSafeboxes(this.getUserId(req));
  }

  @Get(':safeboxId')
  async getSafeboxDetail(
    @Req() req: Request,
    @Param('safeboxId') safeboxId: string,
  ): Promise<{ safebox: SafeboxRecord; members: SafeboxMemberRecord[]; role: string }> {
    return this.safeboxService.getSafeboxDetail(safeboxId, this.getUserId(req));
  }

  @Get(':safeboxId/transactions')
  async getTransactionLedger(
    @Req() req: Request,
    @Param('safeboxId') safeboxId: string,
  ): Promise<SafeboxTxRecord[]> {
    return this.safeboxService.getTransactionLedger(safeboxId, this.getUserId(req));
  }

  @Post(':safeboxId/contribute')
  @HttpCode(HttpStatus.OK)
  async contribute(
    @Req() req: Request,
    @Param('safeboxId') safeboxId: string,
    @Body() dto: ContributeSafeboxDto,
  ) {
    return this.safeboxService.contribute(safeboxId, this.getUserId(req), dto);
  }

  @Post(':safeboxId/withdraw')
  @HttpCode(HttpStatus.OK)
  async withdraw(
    @Req() req: Request,
    @Param('safeboxId') safeboxId: string,
    @Body() dto: WithdrawSafeboxDto,
  ) {
    // Server-side guard inside service blocks non-owner/admin with HTTP 403
    return this.safeboxService.withdraw(safeboxId, this.getUserId(req), dto);
  }

  @Put(':safeboxId/members/role')
  @HttpCode(HttpStatus.OK)
  async updateMemberRole(
    @Req() req: Request,
    @Param('safeboxId') safeboxId: string,
    @Body() dto: UpdateMemberRoleDto,
  ): Promise<SafeboxMemberRecord> {
    // Server-side 3-admin cap enforced inside service
    return this.safeboxService.updateMemberRole(safeboxId, this.getUserId(req), dto);
  }

  @Post(':safeboxId/members')
  @HttpCode(HttpStatus.CREATED)
  async addMember(
    @Req() req: Request,
    @Param('safeboxId') safeboxId: string,
    @Body('userId') newUserId: string,
  ): Promise<SafeboxMemberRecord> {
    return this.safeboxService.addMember(safeboxId, this.getUserId(req), newUserId);
  }

  @Post(':safeboxId/transfer-ownership/initiate')
  async initiateOwnershipTransfer(
    @Req() req: Request,
    @Param('safeboxId') safeboxId: string,
    @Body() dto: InitiateOwnershipTransferDto,
  ) {
    return this.safeboxService.initiateOwnershipTransfer(safeboxId, this.getUserId(req), dto);
  }

  @Post(':safeboxId/transfer-ownership/confirm')
  async confirmOwnershipTransfer(
    @Req() req: Request,
    @Param('safeboxId') safeboxId: string,
    @Body() dto: ConfirmOwnershipTransferDto,
  ) {
    return this.safeboxService.confirmOwnershipTransfer(safeboxId, this.getUserId(req), dto.transferToken);
  }
}
