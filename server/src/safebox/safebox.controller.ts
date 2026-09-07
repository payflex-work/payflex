import {
  Controller,
  Get,
  Post,
  Put,
  Body,
  Param,
  Headers,
  HttpCode,
  HttpStatus,
  UsePipes,
  ValidationPipe,
} from '@nestjs/common';
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

@Controller('api/v1/safebox')
@UsePipes(new ValidationPipe({ transform: true, whitelist: true }))
export class SafeboxController {
  constructor(private readonly safeboxService: SafeboxService) {}

  private getUserId(headers: Record<string, string>): string {
    return headers['x-user-id'] || 'usr_default';
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  async createSafebox(
    @Headers() headers: Record<string, string>,
    @Body() dto: CreateSafeboxDto,
  ): Promise<SafeboxRecord> {
    const userId = this.getUserId(headers);
    return this.safeboxService.createSafebox(userId, dto);
  }

  @Get()
  async getUserSafeboxes(
    @Headers() headers: Record<string, string>,
  ): Promise<{ safebox: SafeboxRecord; role: string }[]> {
    const userId = this.getUserId(headers);
    return this.safeboxService.getUserSafeboxes(userId);
  }

  @Get(':id')
  async getSafeboxDetail(
    @Headers() headers: Record<string, string>,
    @Param('id') id: string,
  ): Promise<{ safebox: SafeboxRecord; members: SafeboxMemberRecord[]; role: string }> {
    const userId = this.getUserId(headers);
    return this.safeboxService.getSafeboxDetail(id, userId);
  }

  @Get(':id/transactions')
  async getTransactionLedger(
    @Headers() headers: Record<string, string>,
    @Param('id') id: string,
  ): Promise<SafeboxTxRecord[]> {
    const userId = this.getUserId(headers);
    return this.safeboxService.getTransactionLedger(id, userId);
  }

  @Post(':id/contribute')
  @HttpCode(HttpStatus.OK)
  async contribute(
    @Headers() headers: Record<string, string>,
    @Param('id') id: string,
    @Body() dto: ContributeSafeboxDto,
  ): Promise<SafeboxTxRecord> {
    const userId = this.getUserId(headers);
    return this.safeboxService.contribute(id, userId, dto);
  }

  @Post(':id/withdraw')
  @HttpCode(HttpStatus.OK)
  async withdraw(
    @Headers() headers: Record<string, string>,
    @Param('id') id: string,
    @Body() dto: WithdrawSafeboxDto,
  ): Promise<SafeboxTxRecord> {
    const userId = this.getUserId(headers);
    // Server-side guard inside service blocks non-owner/admin with HTTP 403
    return this.safeboxService.withdraw(id, userId, dto);
  }

  @Put(':id/members/role')
  @HttpCode(HttpStatus.OK)
  async updateMemberRole(
    @Headers() headers: Record<string, string>,
    @Param('id') id: string,
    @Body() dto: UpdateMemberRoleDto,
  ): Promise<SafeboxMemberRecord> {
    const userId = this.getUserId(headers);
    // Server-side 3-admin cap enforced inside service
    return this.safeboxService.updateMemberRole(id, userId, dto);
  }

  @Post(':id/members')
  @HttpCode(HttpStatus.CREATED)
  async addMember(
    @Headers() headers: Record<string, string>,
    @Param('id') id: string,
    @Body('userId') newUserId: string,
  ): Promise<SafeboxMemberRecord> {
    const userId = this.getUserId(headers);
    return this.safeboxService.addMember(id, userId, newUserId);
  }

  @Post(':id/transfer-ownership/initiate')
  async initiateOwnershipTransfer(
    @Headers() headers: Record<string, string>,
    @Param('id') id: string,
    @Body() dto: InitiateOwnershipTransferDto,
  ) {
    const userId = this.getUserId(headers);
    return this.safeboxService.initiateOwnershipTransfer(id, userId, dto);
  }

  @Post(':id/transfer-ownership/confirm')
  async confirmOwnershipTransfer(
    @Headers() headers: Record<string, string>,
    @Param('id') id: string,
    @Body() dto: ConfirmOwnershipTransferDto,
  ) {
    const userId = this.getUserId(headers);
    return this.safeboxService.confirmOwnershipTransfer(id, userId, dto.transferToken);
  }
}
