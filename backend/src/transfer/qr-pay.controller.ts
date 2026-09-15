import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { Public } from '../auth/public.decorator';
import { QrPayService } from './qr-pay.service';
import { GenerateQrDto } from './dto/qr-pay.dto';

@Controller('users/:id/qr')
export class QrPayController {
  constructor(private readonly qrPay: QrPayService) {}

  @Post('generate')
  generate(@Param('id') id: string, @Body() dto: GenerateQrDto) {
    return this.qrPay.generate(id, dto);
  }
}

/**
 * Public decode endpoint: the PAYER's app calls this after scanning (the
 * payer is not the QR owner, so no :id ownership scope applies). It only
 * verifies the HMAC and returns the payload for the confirm screen.
 */
@Controller('qr')
export class QrDecodeController {
  constructor(private readonly qrPay: QrPayService) {}

  @Public()
  @Get('decode')
  decode(@Query('token') token: string) {
    return this.qrPay.decode(token);
  }
}
