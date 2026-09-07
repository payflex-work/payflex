import { Module } from '@nestjs/common';
import { SafeboxController } from './safebox.controller';
import { SafeboxService } from './safebox.service';

@Module({
  controllers: [SafeboxController],
  providers: [SafeboxService],
  exports: [SafeboxService],
})
export class SafeboxModule {}
