import {
  Controller,
  Get,
  Post,
  Put,
  Body,
  Param,
  Headers,
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

@Controller('safebox')
@UsePipes(new ValidationPipe({ transform: true, whitelist: true }))
export class SafeboxController {
  constructor(private readonly safeboxService: SafeboxService) {}

  private getUserId(req: Request, headers: Record<string, string>): string {
    const user = (req as any).user;
    return user?.appUserId || headers['x-user-id'] || 'usr_default';
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  async createSafebox(
    @Req() req: Request,
    @Headers() headers: Record<string, string>,
    @Body() dto: CreateSafeboxDto,
  ): Promise<SafeboxRecord> {
    const userId = this.getUserId(req, headers);
    return this.safeboxService.createSafebox(userId, dto);
  }

  @Get()
  async getUserSafeboxes(
    @Req() req: Request,
    @Headers() headers: Record<string, string>,
  ): Promise<{ safebox: SafeboxRecord; role: string }[]> {
    const userId = this.getUserId(req, headers);
    return this.safeboxService.getUserSafeboxes(userId);
  }

  @Get(':safeboxId')
  async getSafeboxDetail(
    @Req() req: Request,
    @Headers() headers: Record<string, string>,
    @Param('safeboxId') safeboxId: string,
  ): Promise<{ safebox: SafeboxRecord; members: SafeboxMemberRecord[]; role: string }> {
    const userId = this.getUserId(req, headers);
    return this.safeboxService.getSafeboxDetail(safeboxId, userId);
  }

  @Get(':safeboxId/transactions')
  async getTransactionLedger(
    @Req() req: Request,
    @Headers() headers: Record<string, string>,
    @Param('safeboxId') safeboxId: string,
  ): Promise<SafeboxTxRecord[]> {
    const userId = this.getUserId(req, headers);
    return this.safeboxService.getTransactionLedger(safeboxId, userId);
  }

  @Post(':safeboxId/contribute')
  @HttpCode(HttpStatus.OK)
  async contribute(
    @Req() req: Request,
    @Headers() headers: Record<string, string>,
    @Param('safeboxId') safeboxId: string,
    @Body() dto: ContributeSafeboxDto,
  ): Promise<SafeboxTxRecord> {
    const userId = this.getUserId(req, headers);
    return this.safeboxService.contribute(safeboxId, userId, dto);
  }

  @Post(':safeboxId/withdraw')
  @HttpCode(HttpStatus.OK)
  async withdraw(
    @Req() req: Request,
    @Headers() headers: Record<string, string>,
    @Param('safeboxId') safeboxId: string,
    @Body() dto: WithdrawSafeboxDto,
  ): Promise<SafeboxTxRecord> {
    const userId = this.getUserId(req, headers);
    // Server-side guard inside service blocks non-owner/admin with HTTP 403
    return this.safeboxService.withdraw(safeboxId, userId, dto);
  }

  @Put(':safeboxId/members/role')
  @HttpCode(HttpStatus.OK)
  async updateMemberRole(
    @Req() req: Request,
    @Headers() headers: Record<string, string>,
    @Param('safeboxId') safeboxId: string,
    @Body() dto: UpdateMemberRoleDto,
  ): Promise<SafeboxMemberRecord> {
    const userId = this.getUserId(req, headers);
    // Server-side 3-admin cap enforced inside service
    return this.safeboxService.updateMemberRole(safeboxId, userId, dto);
  }

  @Post(':safeboxId/members')
  @HttpCode(HttpStatus.CREATED)
  async addMember(
    @Req() req: Request,
    @Headers() headers: Record<string, string>,
    @Param('safeboxId') safeboxId: string,
    @Body('userId') newUserId: string,
  ): Promise<SafeboxMemberRecord> {
    const userId = this.getUserId(req, headers);
    return this.safeboxService.addMember(safeboxId, userId, newUserId);
  }

  @Post(':safeboxId/transfer-ownership/initiate')
  async initiateOwnershipTransfer(
    @Req() req: Request,
    @Headers() headers: Record<string, string>,
    @Param('safeboxId') safeboxId: string,
    @Body() dto: InitiateOwnershipTransferDto,
  ) {
    const userId = this.getUserId(req, headers);
    return this.safeboxService.initiateOwnershipTransfer(safeboxId, userId, dto);
  }

  @Post(':safeboxId/transfer-ownership/confirm')
  async confirmOwnershipTransfer(
    @Req() req: Request,
    @Headers() headers: Record<string, string>,
    @Param('safeboxId') safeboxId: string,
    @Body() dto: ConfirmOwnershipTransferDto,
  ) {
    const userId = this.getUserId(req, headers);
    return this.safeboxService.confirmOwnershipTransfer(safeboxId, userId, dto.transferToken);
  }
}
