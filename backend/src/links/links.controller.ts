import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { Public } from '../auth/public.decorator';
import { LinksService, SendViaLinkDto, RegisterClaimableBalanceDto, ClaimLinkDto } from './links.service';

@Controller()
export class LinksController {
  constructor(private readonly links: LinksService) {}

  @Post('users/:id/send-via-link')
  sendViaLink(@Param('id') id: string, @Body() dto: SendViaLinkDto) {
    return this.links.sendViaLink(id, dto);
  }

  /** Sender's app reports the on-chain claimable balance it created. */
  @Post('users/:id/links/:linkId/claimable-balance')
  registerClaimableBalance(
    @Param('id') id: string,
    @Param('linkId') linkId: string,
    @Body() dto: RegisterClaimableBalanceDto,
  ) {
    return this.links.registerClaimableBalance(id, linkId, dto);
  }

  /** Sender's link list. */
  @Get('users/:id/links')
  listForSender(@Param('id') id: string) {
    return this.links.listForSender(id);
  }

  /** Recipient's app claims (after the on-chain claim succeeded). */
  @Post('users/:id/links/:linkId/claim')
  claim(@Param('id') id: string, @Param('linkId') linkId: string, @Body() dto: ClaimLinkDto) {
    return this.links.claim(id, linkId, dto);
  }
}

/** Public: the recipient doesn't have an account yet when previewing. */
@Controller('links')
export class LinkPreviewController {
  constructor(private readonly links: LinksService) {}

  @Public()
  @Get('preview')
  preview(@Query('token') token: string) {
    return this.links.preview(token);
  }
}
