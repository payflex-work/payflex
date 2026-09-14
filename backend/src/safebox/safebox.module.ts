import { Module } from '@nestjs/common';
import { SafeboxController } from './safebox.controller';
import { SafeboxSorobanService } from './safebox-soroban.service';
import { UsersModule } from '../users/users.module';

@Module({
  imports: [UsersModule],
  controllers: [SafeboxController],
  providers: [SafeboxSorobanService],
  exports: [SafeboxSorobanService],
})
export class SafeboxModule {}
