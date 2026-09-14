import { Body, Controller, Get, Param, Patch, Post } from '@nestjs/common';
import { UsersService } from './users.service';
import { CreateUserDto } from './dto/create-user.dto';
import { SetStellarPublicKeyDto } from './dto/set-stellar-public-key.dto';
import { TokenService } from '../token/token.service';
import { Public } from '../auth/public.decorator';

@Controller('users')
export class UsersController {
  constructor(
    private readonly users: UsersService,
    private readonly tokens: TokenService,
  ) {}

  /**
   * Public — there's no token to require yet. Returns a short-lived
   * bootstrap token scoped to exactly one follow-up call
   * (PATCH :id/stellar-public-key) so the app can register the public half
   * of its on-device keypair before a real login (which proves ownership
   * of that key) becomes possible. See AuthGuard's doc comment for the
   * full flow.
   */
  @Public()
  @Post()
  async create(@Body() dto: CreateUserDto) {
    const user = await this.users.getOrCreate(dto);
    // Only a user who hasn't registered a key yet gets a bootstrap token —
    // an existing user (this call is idempotent by phone number) must log
    // in via the normal challenge/signature flow instead. Handing out a
    // fresh bootstrap token here every time would let anyone who can call
    // this public endpoint overwrite an *existing* user's key.
    const bootstrapToken = user.stellarPublicKey ? null : this.tokens.signBootstrapToken(user.id);
    return { user, bootstrapToken };
  }

  @Get(':id')
  findById(@Param('id') id: string) {
    return this.users.findById(id);
  }

  /**
   * Registers the public half of the user's on-device Stellar keypair.
   * Requires the bootstrap token (see above) on first use; keys are
   * immutable afterwards.
   */
  @Patch(':id/stellar-public-key')
  setStellarPublicKey(@Param('id') id: string, @Body() dto: SetStellarPublicKeyDto) {
    return this.users.setStellarPublicKey(id, dto.stellarPublicKey);
  }
}
