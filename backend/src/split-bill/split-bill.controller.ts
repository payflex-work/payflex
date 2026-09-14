import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { SplitBillService, CreateSplitBillDto } from './split-bill.service';
import { HmacTokenService } from '../common/hmac-token.service';

@Controller()
export class SplitBillController {
  constructor(
    private readonly splitBills: SplitBillService,
    private readonly hmacTokens: HmacTokenService,
  ) {}

  @Post('users/:id/split-bills')
  create(@Param('id') id: string, @Body() dto: CreateSplitBillDto) {
    return this.splitBills.create(id, dto);
  }

  @Get('users/:id/split-bills')
  listForUser(@Param('id') id: string) {
    return this.splitBills.listForUser(id);
  }

  @Get('users/:id/split-bills/:splitBillId')
  getDetail(@Param('id') id: string, @Param('splitBillId') splitBillId: string) {
    return this.splitBills.getDetail(id, splitBillId);
  }

  /**
   * Scanning a split-bill QR resolves to this — the token carries the bill
   * id (HMAC-signed); the scanning contributor sees their own share.
   */
  @Get('split-bills/qr')
  getByToken(@Query('token') token: string) {
    const payload = this.hmacTokens.verify<{ billId: string }>(token);
    return this.splitBills.getDetail(payload.billId, payload.billId);
  }
}
