import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { LinksService } from './links.service';
import { SendViaLinkDto } from './dto/send-via-link.dto';
import { Public } from '../auth/public.decorator';

@Controller()
export class LinksController {
  constructor(private readonly links: LinksService) {}

  @Post('users/:id/send-via-link')
  sendViaLink(@Param('id') id: string, @Body() dto: SendViaLinkDto) {
    return this.links.sendViaLink(id, dto);
  }

  /**
   * Public — the whole point of send-via-link is that the recipient may
   * not have a PayFlex account (or the app installed) yet when they
   * first open this. Deliberately narrow: amount/currency/sender name/
   * status only, nothing that would work as a bearer credential on its
   * own (claiming still requires the token itself via POST below).
   */
  @Public()
  @Get('claim/:token')
  previewClaim(@Param('token') token: string) {
    return this.links.previewClaim(token);
  }

  @Post('users/:id/claim/:token')
  claim(@Param('id') id: string, @Param('token') token: string) {
    return this.links.claim(id, token);
  }
}
