import { BadRequestException, Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { TransferService } from './transfer.service';
import { PayTagService } from './paytag.service';
import { CreateTransferDto } from './dto/create-transfer.dto';
import { RecordTransferDto } from './dto/record-transfer.dto';
import { RegisterPayTagDto } from './dto/register-paytag.dto';

@Controller()
export class TransferController {
  constructor(
    private readonly transfers: TransferService,
    private readonly payTags: PayTagService,
  ) {}

  @Post('users/:id/paytag')
  registerPayTag(@Param('id') id: string, @Body() dto: RegisterPayTagDto) {
    return this.payTags.register(id, dto.tag);
  }

  @Get('users/:id/paytag')
  getPayTag(@Param('id') id: string) {
    return this.payTags.getForUser(id);
  }

  @Get('paytag/:tag')
  async resolvePayTag(@Param('tag') tag: string) {
    const user = await this.payTags.resolve(tag);
    // Deliberately narrow: enough to show "sending to <name>" and target a
    // payment, nothing else about the recipient.
    return {
      appUserId: user.id,
      stellarPublicKey: user.stellarPublicKey,
      firstName: user.firstName,
      lastName: user.lastName,
    };
  }

  /**
   * Resolve a transfer target (PayTag or raw public key) to a destination
   * public key + display name, BEFORE the app builds the payment.
   */
  @Post('users/:id/transfers/resolve')
  resolveTarget(@Param('id') id: string, @Body() dto: CreateTransferDto) {
    return this.transfers.resolveTarget(id, dto);
  }

  /**
   * Record a payment the app has already signed and submitted. Verified
   * on-chain before anything is stored — see TransferService.recordTransfer.
   */
  @Post('users/:id/transfers/record')
  recordTransfer(@Param('id') id: string, @Body() dto: RecordTransferDto) {
    return this.transfers.recordTransfer(id, dto);
  }

  @Get('users/:id/transfers')
  listTransfers(@Param('id') id: string, @Query('limit') limit?: string) {
    return this.transfers.listTransfers(id, limit ? Number(limit) : 50);
  }
}
